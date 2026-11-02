`timescale 1ns/1ps
// D11五音色引擎：电钢琴采用衰减FM和独立铃音；吉他采用快速变暗的拨弦瞬态。
// 声音由FPGA逐采样实时合成；没有读取乐器录音或占用TF卡带宽。
module piano28_timbre_engine_d11 #(
    parameter integer MASTER_SHIFT=3, OUTPUT_LIMIT=16384
)(
    input wire clk,rst_n,sample_tick,
    input wire [27:0] key_gate,input wire [335:0] key_pressure,
    input wire signed [3:0] transpose,input wire [2:0] timbre_select,
    output reg signed [15:0] mixed_sample,output reg frame_done,
    output reg [27:0] voice_active,output reg busy,ready,deadline_fault
);
    localparam IDLE=0,ATTACK=1,DECAY=2,SUSTAIN=3,RELEASE=4;
    localparam RUN=0,FADE=1,CLEAR=2;
    reg [1:0] switch_state;reg [2:0] current_timbre;
    reg [8:0] fade_gain;reg [27:0] blocked_keys,fade_keys;
    wire [2:0] requested=(timbre_select<=4)?timbre_select:3'd0;
    // 切换只作用于琴音。5.33ms淡出后用完整一帧清空28个声部，持键须释放后才可重触发。
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin switch_state<=RUN;current_timbre<=0;fade_gain<=256;blocked_keys<=0;fade_keys<=0;end
        else if(sample_tick&&ready)begin
            case(switch_state)
                RUN:begin
                    blocked_keys<=blocked_keys&key_gate;
                    if(requested!=current_timbre)begin switch_state<=FADE;fade_gain<=255;fade_keys<=key_gate;blocked_keys<=key_gate;end
                end
                FADE:begin
                    blocked_keys<=blocked_keys|key_gate;
                    if(fade_gain<=1)begin fade_gain<=0;switch_state<=CLEAR;end
                    else fade_gain<=fade_gain-1'b1;
                end
                CLEAR:begin current_timbre<=requested;switch_state<=RUN;fade_gain<=256;blocked_keys<=key_gate;end
                default:begin switch_state<=CLEAR;fade_gain<=0;end
            endcase
        end
    end
    (* syn_ramstyle="block_ram" *) reg [63:0] context_mem[0:31];
    // 只增加分布式小RAM：独立铃音相位32位、亮度包络24位、音量包络小数8位。
    // 不占用TF卡，也不增加大块采样存储；每声部仍固定32个系统时钟。
    (* syn_ramstyle="distributed_ram" *) reg [63:0] tone_mem[0:31];
    reg [63:0] context_q;
    reg [4:0] init_index,voice_index,slot;
    reg [27:0] gates;reg [335:0] pressures;reg signed [3:0] trans;
    reg [2:0] profile;reg clear_frame;reg [8:0] frame_gain;
    reg [31:0] phase,step,phase_query,phase_next;
    reg [15:0] envelope,next_envelope;reg [11:0] gain,next_gain,pressure;
    reg [2:0] env_state,next_state;reg previous_gate;
    reg [15:0] attack_step,decay_step,sustain_level,release_step;
    reg [31:0] bell_phase,bell_next;
    reg [23:0] brightness,brightness_next;
    reg [7:0] amp_fraction,amp_fraction_next;
    reg [27:0] color_product;reg [15:0] color_env;
    reg signed [32:0] mod_product;reg [31:0] fm_phase;
    reg signed [15:0] fm_sine;
    always @*begin
        // 钢琴/吉他为自然消退；风琴持续保持；弦乐慢起音、慢释放。
        attack_step=512;decay_step=1;sustain_level=0;release_step=32;
        case(profile)
            1:begin attack_step=512;decay_step=2;sustain_level=0;release_step=24;end
            2:begin attack_step=1024;decay_step=32;sustain_level=50000;release_step=256;end
            3:begin attack_step=2048;decay_step=1;sustain_level=0;release_step=64;end
            4:begin attack_step=8;decay_step=2;sustain_level=50000;release_step=2;end
            default:begin end
        endcase
    end
    wire gate_now=gates[voice_index];
    wire signed [12:0] gain_error=$signed({1'b0,pressure})-$signed({1'b0,gain});
    wire signed [12:0] gain_delta=(gain_error>0&&(gain_error>>>6)==0)?13'sd1:gain_error>>>6;
    reg [31:0] phase_for_sample,phase_after_sample;
    reg [15:0] env_after_sample;reg [11:0] gain_after_sample;reg [2:0] state_after_sample;
    reg [15:0] drop;
    reg [23:0] amp_work,amp_drop,bright_drop;
    reg [31:0] bell_for_sample,bell_after_sample;
    reg [23:0] bright_after_sample;
    reg [7:0] fraction_after_sample;
    wire shaped_profile=(profile==1||profile==3);
    wire note_start=gate_now&&!previous_gate;
    always @*begin
        phase_for_sample=phase;phase_after_sample=phase+step;
        env_after_sample=envelope;gain_after_sample=gain;state_after_sample=env_state;drop=decay_step;
        amp_work={envelope,amp_fraction};amp_drop=0;bright_drop=0;
        fraction_after_sample=amp_fraction;bright_after_sample=brightness;
        // 3.5倍铃音使用独立相位累加器，不能直接将回绕后的基频相位乘3.5。
        bell_for_sample=bell_phase;bell_after_sample=bell_phase+(step<<1)+step+(step>>1);
        if(clear_frame)begin
            phase_for_sample=0;phase_after_sample=0;env_after_sample=0;gain_after_sample=0;state_after_sample=IDLE;
        end else if(gate_now&&!previous_gate)begin
            phase_for_sample=0;phase_after_sample=step;env_after_sample=0;gain_after_sample=pressure;state_after_sample=ATTACK;
        end else begin
            if(gate_now&&env_state!=IDLE&&env_state!=RELEASE)gain_after_sample=$signed({1'b0,gain})+gain_delta;
            if(!gate_now&&env_state!=IDLE&&env_state!=RELEASE)state_after_sample=RELEASE;
            else case(env_state)
                IDLE:env_after_sample=0;
                ATTACK:if(envelope>=16'hffff-attack_step)begin env_after_sample=65535;state_after_sample=DECAY;end
                       else env_after_sample=envelope+attack_step;
                DECAY:if(envelope<=sustain_level+drop)begin env_after_sample=sustain_level;state_after_sample=SUSTAIN;end
                      else env_after_sample=envelope-drop;
                SUSTAIN:env_after_sample=sustain_level;
                RELEASE:if(envelope<=release_step)begin env_after_sample=0;state_after_sample=IDLE;end
                        else env_after_sample=envelope-release_step;
                default:begin env_after_sample=0;state_after_sample=IDLE;end
            endcase
        end
        if(shaped_profile)begin
            // 24位指数包络：低音衰减较慢，高音较快；分数位保证尾音平滑。
            if(clear_frame)begin amp_work=0;bright_after_sample=0;bell_for_sample=0;bell_after_sample=0;end
            else if(note_start)begin amp_work=0;bright_after_sample=24'hffff00;bell_for_sample=0;bell_after_sample=(step<<1)+step+(step>>1);end
            else begin
                bright_drop=(profile==3)?(brightness>>11):(brightness>>13);
                bright_after_sample=(brightness<=256)?0:brightness-((bright_drop==0)?24'd1:bright_drop);
                case(env_state)
                    IDLE:amp_work=0;
                    ATTACK:amp_work={env_after_sample,8'd0};
                    DECAY,SUSTAIN:begin
                        if(profile==1)amp_drop=(voice_index<14)?(amp_work>>16):(amp_work>>15);
                        else amp_drop=(voice_index<14)?(amp_work>>14):(amp_work>>13);
                        amp_work=(amp_work<=256)?0:amp_work-((amp_drop==0)?24'd1:amp_drop);
                        if(amp_work==0)state_after_sample=IDLE;
                        else state_after_sample=gate_now?DECAY:RELEASE;
                    end
                    RELEASE:begin
                        amp_drop=(profile==1)?(amp_work>>12):(amp_work>>10);
                        amp_work=(amp_work<=256)?0:amp_work-((amp_drop==0)?24'd1:amp_drop);
                        if(amp_work==0)state_after_sample=IDLE;
                    end
                    default:amp_work=0;
                endcase
            end
            env_after_sample=amp_work[23:8];fraction_after_sample=amp_work[7:0];
        end else begin
            // 钢琴、风琴、弦乐沿用D10计算，附加状态清零。
            bell_for_sample=0;bell_after_sample=0;bright_after_sample=0;fraction_after_sample=0;
        end
    end
    wire [31:0] frequency_step;
    note_frequency28 u_frequency(.key_index(voice_index),.transpose(trans),.phase_step(frequency_step));
    wire signed [15:0] sine;
    sine28_shared u_sine(.clk(clk),.phase(phase_query),.sample_out(sine));
    reg signed [15:0] partial1,partial2,partial3,partial4,partial5,partial7;
    wire signed [19:0] h1={{4{partial1[15]}},partial1},h2={{4{partial2[15]}},partial2},h3={{4{partial3[15]}},partial3};
    wire signed [19:0] h4={{4{partial4[15]}},partial4},h5={{4{partial5[15]}},partial5},h7={{4{partial7[15]}},partial7};
    reg signed [19:0] wave_next,wave,body_wave,bright_wave,bright_scaled;
    reg signed [36:0] bright_product;
    always @*begin
        // 移位配比有明确幅度余量，最高七次泛音在本工程音域/移调范围内低于24kHz。
        case(profile)
            1:wave_next=(h1>>>2); // 电钢琴另一半基音来自随亮度变化的FM载波。
            2:wave_next=(h1>>>2)+(h2>>>3)+(h3>>>3)+(h4>>>4)+(h5>>>5)+(h7>>>5);
            3:wave_next=(h1>>>1)+(h2>>>2)+(h3>>>5); // 强化琴体二次泛音，与电钢琴的铃音/奇次边带区分。
            4:wave_next=(h1>>>2)+(h2>>>3)+(h3>>>4)+(h4>>>4)+(h5>>>5)+(h7>>>5);
            default:wave_next=(h1>>>1)+(h2>>>3)+(h3>>>4)+(h4>>>5)+(h5>>>6)+(h7>>>7);
        endcase
    end
    reg signed [36:0] envelope_product;reg signed [20:0] envelope_scaled;
    reg signed [33:0] pressure_product;reg signed [21:0] voice_sample;
    reg signed [25:0] accumulator;
    reg signed [15:0] limited_mix;reg signed [25:0] fade_product;
    function signed [15:0] master_output;
        input signed [25:0] sum;
        reg signed [25:0] scaled;reg [25:0] magnitude,compressed;
        begin
            scaled=sum>>>MASTER_SHIFT;magnitude=scaled[25]?-scaled:scaled;
            compressed=(magnitude<=8192)?magnitude:8192+((magnitude-8192)>>2);
            if(compressed>OUTPUT_LIMIT)compressed=OUTPUT_LIMIT;
            master_output=scaled[25]?-$signed(compressed[15:0]):$signed(compressed[15:0]);
        end
    endfunction
    always @(posedge clk)begin
        context_q<=context_mem[voice_index];
        if(!ready)begin context_mem[init_index]<=0;tone_mem[init_index]<=0;end
        else if(busy&&slot==31)begin
            context_mem[voice_index]<={phase_next,next_envelope,next_gain,next_state,gate_now};
            tone_mem[voice_index]<={bell_next,brightness_next,amp_fraction_next};
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            ready<=0;init_index<=0;busy<=0;slot<=0;voice_index<=0;deadline_fault<=0;frame_done<=0;mixed_sample<=0;voice_active<=0;
            gates<=0;pressures<=0;trans<=0;profile<=0;clear_frame<=0;frame_gain<=256;
            phase<=0;step<=0;phase_query<=0;phase_next<=0;envelope<=0;next_envelope<=0;gain<=0;next_gain<=0;pressure<=0;
            env_state<=0;next_state<=0;previous_gate<=0;accumulator<=0;
            partial1<=0;partial2<=0;partial3<=0;partial4<=0;partial5<=0;partial7<=0;wave<=0;
            envelope_product<=0;envelope_scaled<=0;pressure_product<=0;voice_sample<=0;limited_mix<=0;fade_product<=0;
            bell_phase<=0;bell_next<=0;brightness<=0;brightness_next<=0;amp_fraction<=0;amp_fraction_next<=0;
            color_product<=0;color_env<=0;mod_product<=0;fm_phase<=0;fm_sine<=0;
            body_wave<=0;bright_wave<=0;bright_product<=0;bright_scaled<=0;
        end else begin
            frame_done<=0;
            if(!ready)begin if(init_index==31)ready<=1;else init_index<=init_index+1'b1;end
            else if(sample_tick&&!busy)begin
                // 全帧快照：切音色、力度和移调均不可能在28个声部计算中途撕裂。
                gates<=(switch_state==CLEAR)?28'd0:(switch_state==FADE)?(key_gate&fade_keys):(key_gate&~blocked_keys);
                pressures<=key_pressure;trans<=transpose;profile<=current_timbre;clear_frame<=(switch_state==CLEAR);frame_gain<=fade_gain;
                voice_index<=0;slot<=0;busy<=1;accumulator<=0;
            end else if(busy)begin
                if(sample_tick)deadline_fault<=1;
                slot<=slot+1'b1;
                case(slot)
                    0:begin step<=frequency_step;pressure<=pressures[voice_index*12+:12];end
                    1:begin phase<=context_q[63:32];envelope<=context_q[31:16];gain<=context_q[15:4];env_state<=context_q[3:1];previous_gate<=context_q[0];
                        {bell_phase,brightness,amp_fraction}<=tone_mem[voice_index];end
                    2:begin phase_query<=phase_for_sample;phase_next<=phase_after_sample;next_envelope<=env_after_sample;next_gain<=gain_after_sample;next_state<=state_after_sample;
                        bell_next<=bell_after_sample;brightness_next<=bright_after_sample;amp_fraction_next<=fraction_after_sample;end
                    3:phase_query<=phase_for_sample<<1;
                    4:begin phase_query<=phase_for_sample+(phase_for_sample<<1);color_product<=brightness_next[23:8]*next_gain;end
                    5:begin phase_query<=phase_for_sample<<2;
                        // 力度连续调节亮度，无硬阈值；高音降低FM深度，压低高次边带。
                        if(profile==3)color_env<=(brightness_next[23:8]>>2)+(color_product>>12)-(color_product>>14);
                        else if(voice_index>=21)color_env<=(brightness_next[23:8]>>4)+(color_product>>16);
                        else color_env<=(brightness_next[23:8]>>2)+(color_product>>14);
                    end
                    6:phase_query<=phase_for_sample+(phase_for_sample<<2);
                    // 七次泛音使用整倍相位，避免用回绕后的相位作非整数倍导致周期接缝。
                    7:begin phase_query<=(profile==1)?bell_for_sample:(phase_for_sample<<3)-phase_for_sample;partial1<=sine;end
                    8:partial2<=sine;
                    9:begin partial3<=sine;mod_product<=partial2*$signed({1'b0,color_env});end
                    10:begin partial4<=sine;fm_phase<=phase_for_sample+(mod_product>>>1);end
                    11:begin partial5<=sine;phase_query<=fm_phase;end
                    12:partial7<=sine;
                    13:begin body_wave<=wave_next;
                        if(profile==3)bright_wave<=(h2>>>3)+(h3>>>4)+(h4>>>5)+(h5>>>6)+(h7>>>7);
                        else bright_wave<=(h7>>>1)+(h5>>>7); // 此处h7实际为独立3.5倍铃音，让短音也具有清晰金属起音。
                    end
                    14:bright_product<=bright_wave*$signed({1'b0,color_env});
                    15:bright_scaled<=bright_product>>>16;
                    16:fm_sine<=sine;
                    17:begin
                        if(profile==1)wave<=body_wave+($signed({{4{fm_sine[15]}},fm_sine})>>>2)+bright_scaled;
                        else if(profile==3)wave<=body_wave+bright_scaled;
                        else wave<=body_wave;
                    end
                    18:envelope_product<=wave*$signed({1'b0,next_envelope});
                    19:envelope_scaled<=envelope_product>>>16;
                    20:pressure_product<=envelope_scaled*$signed({1'b0,next_gain});
                    21:voice_sample<=(next_state==IDLE)?22'sd0:pressure_product>>>12;
                    22:accumulator<=accumulator+voice_sample;
                    24:limited_mix<=master_output(accumulator);
                    25:fade_product<=limited_mix*$signed({1'b0,frame_gain});
                    31:begin
                        voice_active[voice_index]<=(next_state!=IDLE);
                        if(voice_index==27)begin mixed_sample<=fade_product>>>8;frame_done<=1;busy<=0;end
                        else voice_index<=voice_index+1'b1;
                    end
                    default:begin end
                endcase
            end
        end
    end
endmodule
