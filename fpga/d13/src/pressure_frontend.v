`timescale 1ns/1ps
module pressure_frontend #(
    parameter [69:0] BASELINE = {7{10'd0}},       // 七键空载 ADC 值，CH0 在最低十位
    parameter [69:0] FULL_SCALE = {7{10'd1023}},  // 七键常用最大值，须逐键实物标定
    parameter integer PRESS_ON = 160,           // 归一化 0～4095 范围内的按下门限
    parameter integer PRESS_OFF = 100           // 较低的松开门限，防止反复触发
)(
    input wire clk, input wire rst_n,
    input wire raw_valid, input wire [2:0] raw_channel,
    input wire [9:0] raw_sample,                 // ADC 是十位；内部音量才使用十二位
    output wire [6:0] key_gate,                  // 七键分别的按下状态
    output wire [83:0] key_pressure              // 七路独立持续音量，0～4095
);
    genvar k;
    generate for (k = 0; k < 7; k = k + 1) begin : g_key
        localparam [9:0] BASE = BASELINE[k*10 +: 10];
        localparam [9:0] FULL = FULL_SCALE[k*10 +: 10];
        localparam integer SPAN = (FULL > BASE) ? FULL - BASE : 1; // 无效标定也避免除零
        localparam integer RAW_ON = BASE + (PRESS_ON * SPAN + 4094) / 4095; // 按下门限换回 ADC 单位，向上取整
        localparam integer RAW_OFF = BASE + ((PRESS_OFF + 1) * SPAN - 1) / 4095; // 与整数归一化后的 <= 门限严格等价
        reg [9:0] filtered;                     // 每键自己的滤波状态
        reg [11:0] normalized_reg;             // 单独寄存归一化音量，切断到声音增益的长组合路径
        reg gate;
        wire signed [10:0] difference = $signed({1'b0, raw_sample}) - $signed({1'b0, filtered});
        reg signed [10:0] filter_step;
        always @* begin
            filter_step = difference >>> 2;    // 每轮向目标移动差值的 1/4
            if (difference > 0 && filter_step == 0) filter_step = 1; // 避免小正差停住
        end
        wire signed [10:0] next_filter = $signed({1'b0, filtered}) + filter_step;
        function [11:0] normalize;             // 标定区间映射为音量，FSR 不作准确测力仪
            input [9:0] value;
            reg [23:0] numerator, quotient;
            begin
                numerator = (value > BASE) ? (value - BASE) * 24'd4095 : 24'd0;
                quotient = numerator / SPAN;   // 除数是编译时常量，各键可独立标定
                if (FULL <= BASE || value <= BASE) normalize = 0;
                else if (value >= FULL) normalize = 4095;
                else normalize = quotient[11:0];
            end
        endfunction
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin filtered <= BASE; gate <= 0; normalized_reg <= 0; end
            else begin
                normalized_reg <= normalize(filtered); // 延迟一个系统周期，50 MHz 时仅 20 ns
                if (raw_valid && raw_channel == k) begin
                    filtered <= next_filter[9:0];
                    if (FULL <= BASE) gate <= 0; // 无效标定禁用该键
                    else if (!gate && next_filter[9:0] >= RAW_ON) gate <= 1;
                    else if (gate && next_filter[9:0] <= RAW_OFF) gate <= 0;
                end
            end
        end
        assign key_gate[k] = gate;
        assign key_pressure[k*12 +: 12] = normalized_reg; // 流水处理不改变 ADC 本身的精度
    end endgenerate
endmodule
