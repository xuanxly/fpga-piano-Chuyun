`timescale 1ns/1ps
module piano28_engine #(
    parameter [15:0] ATTACK_STEP=512,DECAY_STEP=4,SUSTAIN_LEVEL=22000,RELEASE_STEP=16,
    parameter integer MASTER_SHIFT=3, OUTPUT_LIMIT=16384
)(
    input wire clk,rst_n,sample_tick, input wire [27:0] key_gate,input wire [335:0] key_pressure,
    input wire signed [3:0] transpose,
    output reg signed [15:0] mixed_sample,output reg frame_done,output reg [27:0] voice_active,
    output reg busy,ready,deadline_fault
);
    // 64位上下文：相位32、包络16、压力增益12、状态3、上一帧持键1；28键各自独立。
    (* syn_ramstyle="block_ram" *) reg [63:0] context_mem[0:31];
    reg [63:0] context_q;
    reg [4:0] init_index,voice_index,slot;
    reg [27:0] gates;reg [335:0] pressures;reg signed [3:0] trans;
    reg [31:0] phase,step,phase_query,phase_next; reg [15:0] envelope,next_envelope;
    reg [11:0] gain,next_gain,pressure;reg [2:0] env_state,next_state;reg previous_gate;
    reg signed [23:0] accumulator;
    localparam IDLE=0,ATTACK=1,DECAY=2,SUSTAIN=3,RELEASE=4;
    wire gate_now=gates[voice_index];
    wire signed [12:0] gain_error=$signed({1'b0,pressure})-$signed({1'b0,gain});
    wire signed [12:0] gain_delta=(gain_error>0 && (gain_error>>>6)==0) ? 13'sd1 : gain_error>>>6;
    reg [31:0] phase_for_sample,phase_after_sample;
    reg [15:0] env_after_sample;reg [11:0] gain_after_sample;reg [2:0] state_after_sample;
    always @* begin
        phase_for_sample=phase;phase_after_sample=phase+step;env_after_sample=envelope;gain_after_sample=gain;state_after_sample=env_state;
        if(gate_now && !previous_gate) begin
            phase_for_sample=0;phase_after_sample=step;env_after_sample=0;gain_after_sample=pressure;state_after_sample=ATTACK;
        end else begin
            if(gate_now && env_state!=IDLE && env_state!=RELEASE) gain_after_sample=$signed({1'b0,gain})+gain_delta;
            if(!gate_now && env_state!=IDLE && env_state!=RELEASE) state_after_sample=RELEASE;
            else case(env_state)
                IDLE:env_after_sample=0;
                ATTACK:if(envelope>=16'hffff-ATTACK_STEP) begin env_after_sample=65535;state_after_sample=DECAY;end
                       else env_after_sample=envelope+ATTACK_STEP;
                DECAY:if(envelope<=SUSTAIN_LEVEL+DECAY_STEP) begin env_after_sample=SUSTAIN_LEVEL;state_after_sample=SUSTAIN;end
                      else env_after_sample=envelope-DECAY_STEP;
                SUSTAIN:env_after_sample=SUSTAIN_LEVEL;
                RELEASE:if(envelope<=RELEASE_STEP) begin env_after_sample=0;state_after_sample=IDLE;end
                        else env_after_sample=envelope-RELEASE_STEP;
                default:begin env_after_sample=0;state_after_sample=IDLE;end
            endcase
        end
    end
    wire [31:0] frequency_step;
    note_frequency28 u_frequency(.key_index(voice_index),.transpose(trans),.phase_step(frequency_step));
    wire signed [15:0] sine;
    sine28_shared u_sine(.clk(clk),.phase(phase_query),.sample_out(sine));
    reg signed [15:0] fundamental,harmonic2,harmonic3;
    wire signed [17:0] f_ext={{2{fundamental[15]}},fundamental};
    wire signed [17:0] h2_ext={{2{harmonic2[15]}},harmonic2},h3_ext={{2{harmonic3[15]}},harmonic3};
    reg signed [17:0] wave;
    reg signed [34:0] envelope_product; reg signed [18:0] envelope_scaled;
    reg signed [31:0] pressure_product; reg signed [19:0] voice_sample;
    function signed [15:0] master_output;
        input signed [23:0] sum;
        reg signed [23:0] scaled;reg [23:0] magnitude,compressed;
        begin
            scaled=sum >>> MASTER_SHIFT;magnitude=scaled[23] ? -scaled : scaled;
            compressed=(magnitude<=8192) ? magnitude : 8192+((magnitude-8192)>>2); // 固定软拐点，不随按键数改变增益
            if(compressed>OUTPUT_LIMIT) compressed=OUTPUT_LIMIT; // 耳机首版保守数字峰值，不能换算成声压保证
            master_output=scaled[23] ? -$signed(compressed[15:0]) : $signed(compressed[15:0]);
        end
    endfunction
    always @(posedge clk) begin
        context_q<=context_mem[voice_index];
        if(!ready) context_mem[init_index]<=0;
        else if(busy && slot==31) context_mem[voice_index]<={phase_next,next_envelope,next_gain,next_state,gate_now};
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            ready<=0;init_index<=0;busy<=0;slot<=0;voice_index<=0;deadline_fault<=0;frame_done<=0;mixed_sample<=0;voice_active<=0;
            gates<=0;pressures<=0;trans<=0;phase<=0;step<=0;phase_query<=0;phase_next<=0;envelope<=0;next_envelope<=0;
            gain<=0;next_gain<=0;pressure<=0;env_state<=0;next_state<=0;previous_gate<=0;
            accumulator<=0;fundamental<=0;harmonic2<=0;harmonic3<=0;wave<=0;envelope_product<=0;envelope_scaled<=0;pressure_product<=0;voice_sample<=0;
        end else begin
            frame_done<=0;
            if(!ready) begin if(init_index==31) ready<=1;else init_index<=init_index+1'b1;end
            else if(sample_tick && !busy) begin
                gates<=key_gate;pressures<=key_pressure;trans<=transpose;voice_index<=0;slot<=0;busy<=1;accumulator<=0;
            end else if(busy) begin
                if(sample_tick) deadline_fault<=1;       // 硬截止时间自检；不改变DAC连续帧节拍
                slot<=slot+1'b1;
                case(slot)
                    0:begin step<=frequency_step;pressure<=pressures[voice_index*12 +: 12];end
                    1:begin phase<=context_q[63:32];envelope<=context_q[31:16];gain<=context_q[15:4];env_state<=context_q[3:1];previous_gate<=context_q[0];end
                    2:begin
                        phase_query<=phase_for_sample;phase_next<=phase_after_sample;next_envelope<=env_after_sample;
                        next_gain<=gain_after_sample;next_state<=state_after_sample;
                    end
                    3:phase_query<={phase_for_sample[30:0],1'b0};
                    4:phase_query<=phase_for_sample+{phase_for_sample[30:0],1'b0};
                    7:fundamental<=sine;
                    8:harmonic2<=sine;
                    9:harmonic3<=sine;
                    10:wave<=(f_ext>>>1)+(h2_ext>>>3)+(h3_ext>>>4);
                    11:envelope_product<=wave*$signed({1'b0,next_envelope});
                    12:envelope_scaled<=envelope_product>>>16;
                    13:pressure_product<=envelope_scaled*$signed({1'b0,next_gain});
                    14:voice_sample<=(next_state==IDLE) ? 20'sd0 : pressure_product>>>12;
                    15:accumulator<=accumulator+voice_sample;
                    31:begin
                        voice_active[voice_index]<=(next_state!=IDLE);
                        if(voice_index==27) begin mixed_sample<=master_output(accumulator);frame_done<=1;busy<=0;end
                        else voice_index<=voice_index+1'b1;
                    end
                    default:begin end
                endcase
            end
        end
    end
endmodule
