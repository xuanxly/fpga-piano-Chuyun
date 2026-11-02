`timescale 1ns/1ps
module piano_voice #(
    parameter [15:0] ATTACK_STEP = 16'd512,  // 48 kHz 下约 2.7 ms 起音
    parameter [15:0] DECAY_STEP = 16'd4,     // 约 227 ms 衰减到保持值
    parameter [15:0] SUSTAIN_LEVEL = 16'd22000,
    parameter [15:0] RELEASE_STEP = 16'd16   // 保持段松键约 29 ms 释放，起音峰值松键更长
)(
    input wire clk, input wire rst_n, input wire sample_tick,
    input wire note_start, input wire gate,
    input wire [31:0] phase_step, input wire [11:0] pressure,
    output reg signed [15:0] sample_out,
    output wire active
);
    localparam IDLE=3'd0, ATTACK=3'd1, DECAY=3'd2, SUSTAIN=3'd3, RELEASE=3'd4;
    reg [2:0] state;
    reg [15:0] envelope;
    reg [11:0] pressure_gain;
    wire signed [15:0] wave;
    piano_osc u_osc(clk, rst_n, sample_tick, note_start, phase_step, wave);
    wire signed [12:0] gain_error = $signed({1'b0, pressure}) - $signed({1'b0, pressure_gain});
    reg signed [12:0] gain_step;
    always @* begin
        gain_step = gain_error >>> 6;       // 每个采样点平滑持续压力，约 1.3 ms 时间常数
        if (gain_error > 0 && gain_step == 0) gain_step = 1;
    end
    wire signed [12:0] next_gain = $signed({1'b0, pressure_gain}) + gain_step;
    reg signed [32:0] envelope_product;
    reg signed [29:0] pressure_product;
    wire signed [16:0] envelope_scaled = envelope_product[32:16]; // 包络乘积恢复原幅度单位
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; envelope <= 0; pressure_gain <= 0;
            envelope_product <= 0; pressure_product <= 0; sample_out <= 0;
        end else begin
            envelope_product <= wave * $signed({1'b0, envelope}); // 第一级乘法，给时序留出余量
            pressure_product <= envelope_scaled * $signed({1'b0, pressure_gain}); // 压力只乘一次
            if (state == IDLE) sample_out <= 0;
            else sample_out <= pressure_product[27:12]; // 12 位压力增益除以 4096
            if (note_start) begin
                state <= ATTACK; envelope <= 0; pressure_gain <= pressure;
                envelope_product <= 0; pressure_product <= 0; sample_out <= 0; // 清除旧声部尾音数据
            end else if (sample_tick) begin
                if (gate && state != RELEASE && state != IDLE) pressure_gain <= next_gain[11:0];
                // 松键后冻结最后一个压力增益，让包络释放；压力归零不会硬切断声音。
                if (!gate && state != IDLE && state != RELEASE) state <= RELEASE;
                else case (state)
                    IDLE: envelope <= 0;
                    ATTACK: begin
                        if (envelope >= 16'hffff - ATTACK_STEP) begin envelope <= 16'hffff; state <= DECAY; end
                        else envelope <= envelope + ATTACK_STEP;
                    end
                    DECAY: begin
                        if (envelope <= SUSTAIN_LEVEL + DECAY_STEP) begin envelope <= SUSTAIN_LEVEL; state <= SUSTAIN; end
                        else envelope <= envelope - DECAY_STEP;
                    end
                    SUSTAIN: envelope <= SUSTAIN_LEVEL;
                    RELEASE: begin
                        if (envelope <= RELEASE_STEP) begin envelope <= 0; state <= IDLE; sample_out <= 0; end
                        else envelope <= envelope - RELEASE_STEP;
                    end
                    default: begin state <= IDLE; envelope <= 0; end
                endcase
            end
        end
    end
    assign active = (state != IDLE); // 释放尾音也占用声部，但允许分配器优先复用
endmodule
