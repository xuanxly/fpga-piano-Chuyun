`timescale 1ns/1ps
module piano28_core #(
    parameter integer CLK_HZ=50000000, AMP_STARTUP_CYCLES=CLK_HZ/50, ENABLE_TOUCH=0, ENABLE_MEDIA=0, ENABLE_TIMBRE=0, ENABLE_EFFECTS=0, ENABLE_NEW_APPS=0,
    parameter [279:0] PRESSURE_BASELINE={28{10'd0}},PRESSURE_FULL_SCALE={28{10'd1023}}
)(
    input wire sys_clk,rst_n,input wire [3:0] adc_miso,input wire enc_a,enc_b,dark_button_n,
    output wire adc_cs_n,adc_sck,adc_mosi,output wire [9:0] transpose_led,output wire dark_led,
    output wire dac_bck,dac_ws,dac_din,output reg pa_en,
    output wire monitor_valid,output wire signed [15:0] monitor_pcm,
    output wire [27:0] monitor_keys,output wire signed [3:0] monitor_transpose,output wire monitor_dark,
    output wire [2:0] fault,                      // 仿真与内部观察接口，不增加板上GPIO
    output wire monitor_adc_valid,monitor_engine_done,monitor_engine_ready,
    input wire validation_page,validation_run,input wire [5:0] validation_count,
    input wire [2:0] fx_enabled,input wire [20:0] fx_levels,
    output wire i2s_bclk,i2s_lrclk,i2s_data,output wire [191:0] verify_status,
    input wire [27:0] touch_keys,                 // ENABLE_TOUCH=0时保持原有音频回归行为
    input wire [6:0] volume_percent,
    input wire [2:0] timbre_select,           // D10全局音色；旧工程ENABLE_TIMBRE=0时不使用
    input wire transpose_set_valid,          // 触摸设值只影响移调，不改变音量/音色
    input wire signed [3:0] transpose_set,
    input wire playback_exclusive,input wire signed [15:0] playback_l,playback_r,
    output wire [4:0] effect_state,output wire record_valid,output wire signed [15:0] record_pcm,output wire monitor_sample_tick
);
    wire reset_n,sample_tick,raw_valid,engine_done;
    wire [4:0] raw_key;wire [9:0] raw_sample;
    wire [27:0] key_gate,voice_active;wire [335:0] key_pressure;
    wire signed [3:0] transpose;wire dark_mode;
    wire signed [15:0] mixed,audio_sample,audio_sample_r,filtered_sample;
    wire [27:0] merged_keys;wire [335:0] merged_pressure;
    touch_merge28 u_merge(.physical_keys(key_gate),.touch_keys(ENABLE_TOUCH ? touch_keys : 28'd0),
        .physical_pressure(key_pressure),.keys(merged_keys),.pressure(merged_pressure));
    wire engine_ready,engine_busy,vibrato_enable;
    wire verifying=ENABLE_NEW_APPS&&validation_page&&validation_run;
    wire [27:0] synth_keys=verifying?28'd0:merged_keys;
    reset_sync u_reset(.clk(sys_clk),.ext_rst_n(rst_n),.rst_n(reset_n));
    mcp3008_scan28 #(.CLK_HZ(CLK_HZ)) u_adc(.clk(sys_clk),.rst_n(reset_n),.adc_miso(adc_miso),
        .adc_cs_n(adc_cs_n),.adc_sck(adc_sck),.adc_mosi(adc_mosi),.raw_valid(raw_valid),.raw_key(raw_key),.raw_sample(raw_sample),.fault(fault[0]));
    pressure28_frontend #(.BASELINE(PRESSURE_BASELINE),.FULL_SCALE(PRESSURE_FULL_SCALE)) u_pressure(
        .clk(sys_clk),.rst_n(reset_n),.raw_valid(raw_valid),.raw_key(raw_key),.raw_sample(raw_sample),
        .key_gate(key_gate),.key_pressure(key_pressure),.fault(fault[1]),.update_valid(),.update_key());
    instrument_controls #(.CLK_HZ(CLK_HZ),.ENABLE_TRANSPOSE_SET(ENABLE_TOUCH),.ENABLE_TIMBRE_EFFECT(ENABLE_EFFECTS)) u_controls(.clk(sys_clk),.rst_n(reset_n),.enc_a(enc_a),.enc_b(enc_b),
        .dark_button_n(dark_button_n),.timbre_select(timbre_select),.vibrato_enable(vibrato_enable),.effect_state(effect_state),.transpose(transpose),.dark_mode(dark_mode),.transpose_led(transpose_led),.dark_led(dark_led),
        .transpose_set_valid(transpose_set_valid),.transpose_set(transpose_set));
    generate if(ENABLE_TIMBRE)begin:timbre_engine
    piano28_timbre_engine #(.ENABLE_VIBRATO(ENABLE_EFFECTS)) u_engine(.vibrato_enable(vibrato_enable),.clk(sys_clk),.rst_n(reset_n),.sample_tick(sample_tick),.key_gate(synth_keys),.key_pressure(merged_pressure),
        .transpose(transpose),.timbre_select(timbre_select),.mixed_sample(mixed),.frame_done(engine_done),.voice_active(voice_active),
        .busy(engine_busy),.ready(engine_ready),.deadline_fault(fault[2]));
    end else begin:legacy_engine
    piano28_engine u_engine(.clk(sys_clk),.rst_n(reset_n),.sample_tick(sample_tick),.key_gate(synth_keys),.key_pressure(merged_pressure),
        .transpose(transpose),.mixed_sample(mixed),.frame_done(engine_done),.voice_active(voice_active),
        .busy(engine_busy),.ready(engine_ready),.deadline_fault(fault[2]));
    end endgenerate
    tone_filter u_tone(.clk(sys_clk),.rst_n(reset_n),.sample_tick(engine_done),.dark_mode(dark_mode),.sample_in(mixed),.sample_out(filtered_sample));
    reg filtered_valid;
    always @(posedge sys_clk or negedge reset_n)
        if(!reset_n) filtered_valid<=0;else filtered_valid<=engine_done;
    reg playback_valid;
    always @(posedge sys_clk or negedge reset_n)
        if(!reset_n)playback_valid<=0;else playback_valid<=sample_tick;
    wire fx_valid,fx_ready,fx_busy,fx_fault,fx_clipped;wire signed [15:0] effected;
    wire test_valid,test_busy,test_ready,test_fault;wire signed [15:0] test_pcm;wire [5:0] test_units;
    generate if(ENABLE_NEW_APPS)begin:new_apps
        audio_effects28 u_fx(.clk(sys_clk),.rst_n(reset_n),.sample_valid(filtered_valid),.sample_in(filtered_sample),
            .enabled(fx_enabled),.reverb_level(fx_levels[6:0]),.echo_level(fx_levels[13:7]),.chorus_level(fx_levels[20:14]),
            .sample_out(effected),.out_valid(fx_valid),.ready(fx_ready),.busy(fx_busy),.fault(fx_fault),.clipped(fx_clipped));
        validation_tones32 u_test(.clk(sys_clk),.rst_n(reset_n),.sample_tick(sample_tick),.enable(verifying&&validation_run),
            .count(validation_count),.pcm(test_pcm),.valid(test_valid),.busy(test_busy),.ready(test_ready),.fault(test_fault),.active_units(test_units));
        wire unused_i2s_tick;
        i2s_standard_tx u_i2s(.clk(sys_clk),.rst_n(reset_n),.sample_l(audio_sample),.sample_r(audio_sample_r),
            .bclk(i2s_bclk),.lrclk(i2s_lrclk),.data(i2s_data),.frame_tick(unused_i2s_tick));
        audio_verify_monitor u_meter(.clk(sys_clk),.rst_n(reset_n),.frame_tick(sample_tick),.engine_busy(engine_busy),.engine_done(engine_done),
            .keys(synth_keys),.voices(voice_active),.pcm(audio_sample),.faults({test_fault,fx_fault,fx_clipped,2'd0,fault}),.test_units(test_units),.status(verify_status));
    end else begin:no_new_apps
        assign effected=filtered_sample;assign fx_valid=filtered_valid;assign fx_ready=1;assign fx_busy=0;assign fx_fault=0;assign fx_clipped=0;
        assign test_valid=0;assign test_busy=0;assign test_ready=0;assign test_fault=0;assign test_pcm=0;assign test_units=0;
        assign i2s_bclk=0;assign i2s_lrclk=0;assign i2s_data=0;assign verify_status=0;
    end endgenerate
    wire source_is_file=ENABLE_MEDIA&&playback_exclusive;
    wire source_valid=source_is_file?playback_valid:verifying?test_valid:fx_valid;
    wire signed [15:0] source_l=source_is_file?playback_l:verifying?test_pcm:effected;
    wire signed [15:0] source_r=source_is_file?playback_r:verifying?test_pcm:effected;
    assign record_valid=fx_valid;assign record_pcm=effected; // 录音旁路主音量，仍含压力/移调/明暗。
    assign monitor_sample_tick=sample_tick;
    generate if(ENABLE_TOUCH) begin:volume_enabled
        master_volume28 u_volume(.clk(sys_clk),.rst_n(reset_n),.sample_valid(source_valid),
            .sample_in(source_l),.percent(volume_percent),.sample_out(audio_sample),.gain());
        if(ENABLE_MEDIA)begin:stereo
            master_volume28 u_volume_r(.clk(sys_clk),.rst_n(reset_n),.sample_valid(source_valid),
                .sample_in(source_r),.percent(volume_percent),.sample_out(audio_sample_r),.gain());
        end else begin:mono assign audio_sample_r=audio_sample;end
    end else begin:volume_bypass
        assign audio_sample=filtered_sample;assign audio_sample_r=filtered_sample;
    end endgenerate
    pt8211_tx #(.CLK_HZ(CLK_HZ),.SAMPLE_HZ(48000)) u_pt8211_tx(.clk(sys_clk),.rst_n(reset_n),
        .sample_l(audio_sample),.sample_r(audio_sample_r),.sample_tick(sample_tick),.dac_bck(dac_bck),.dac_ws(dac_ws),.dac_din(dac_din));
    assign monitor_valid=sample_tick;assign monitor_pcm=audio_sample;
    assign monitor_keys=merged_keys;assign monitor_transpose=transpose;assign monitor_dark=dark_mode;
    assign monitor_adc_valid=raw_valid;
    assign monitor_engine_done=engine_done;
    assign monitor_engine_ready=engine_ready;
    reg [31:0] amp_count;
    always @(posedge sys_clk or negedge reset_n) begin
        if(!reset_n) begin amp_count<=0;pa_en<=1;end
        else if(amp_count<AMP_STARTUP_CYCLES) begin amp_count<=amp_count+1'b1;pa_en<=1;end
        else pa_en<=|fault;                       // J25耳机也经过NS4263，正常时PA_EN=0；错误时静音
    end
endmodule
