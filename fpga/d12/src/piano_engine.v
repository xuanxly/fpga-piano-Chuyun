`timescale 1ns/1ps
module piano_engine (
    input wire clk, input wire rst_n, input wire sample_tick,
    input wire [6:0] key_gate, input wire [83:0] key_pressure,
    input wire signed [3:0] transpose, input wire dark_mode,
    output wire signed [15:0] sample_out,
    output wire [3:0] voice_active       // 用于仿真观察和后续调试
);
    wire [3:0] voice_gate, note_start;
    wire [11:0] voice_key;
    wire signed [15:0] voice_sample [0:3];
    voice_allocator u_allocator(clk, rst_n, sample_tick, key_gate, voice_active, voice_gate, note_start, voice_key);
    genvar v;
    generate for (v=0; v<4; v=v+1) begin : g_voice
        wire [2:0] owner = voice_key[v*3 +: 3];
        wire [31:0] step;
        wire [11:0] pressure = (owner < 7) ? key_pressure[owner*12 +: 12] : 12'd0;
        note_frequency u_frequency(owner, transpose, step); // 每个声部独立音高，同一个全局变调量
        piano_voice u_voice(clk, rst_n, sample_tick, note_start[v], voice_gate[v], step, pressure,
                            voice_sample[v], voice_active[v]); // 实际实例化四个合成声部
    end endgenerate
    wire signed [17:0] mixed =
        $signed({{2{voice_sample[0][15]}}, voice_sample[0]}) +
        $signed({{2{voice_sample[1][15]}}, voice_sample[1]}) +
        $signed({{2{voice_sample[2][15]}}, voice_sample[2]}) +
        $signed({{2{voice_sample[3][15]}}, voice_sample[3]}); // 扩位求和避免和弦溢出
    wire signed [15:0] scaled_mix = mixed[17:2];            // 固定除以四，留出四复音余量
    tone_filter u_tone(clk, rst_n, sample_tick, dark_mode, scaled_mix, sample_out); // 明暗处理只用一份
endmodule
