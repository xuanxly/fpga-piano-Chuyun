`timescale 1ns/1ps
module tone_filter (
    input wire clk, input wire rst_n, input wire sample_tick,
    input wire dark_mode, input wire signed [15:0] sample_in,
    output reg signed [15:0] sample_out
);
    reg signed [23:0] lowpass_q8;      // 低通状态保留八位小数，减少截断误差
    reg [8:0] blend;                   // 正常 0，偏暗 256，切换时渐变
    wire signed [23:0] input_q8 = {sample_in, 8'd0};
    wire signed [24:0] input_ext = $signed({input_q8[23], input_q8}); // 拼接默认无符号，必须显式转回有符号
    wire signed [24:0] lowpass_ext = $signed({lowpass_q8[23], lowpass_q8});
    wire signed [24:0] filter_error = input_ext - lowpass_ext;
    wire signed [24:0] next_lowpass = lowpass_ext + (filter_error >>> 3); // 正负半周都使用算术右移
    wire signed [15:0] filtered = lowpass_q8[23:8];
    wire signed [16:0] tone_difference = {filtered[15], filtered} - {sample_in[15], sample_in};
    wire signed [26:0] blend_product = tone_difference * $signed({1'b0, blend});
    wire signed [16:0] correction = blend_product[24:8];
    wire signed [17:0] result = $signed({{2{sample_in[15]}}, sample_in}) + $signed({correction[16], correction});
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin lowpass_q8 <= 0; blend <= 0; sample_out <= 0; end
        else if (sample_tick) begin
            lowpass_q8 <= next_lowpass[23:0];
            if (dark_mode && blend < 256) blend <= blend + 9'd4;
            else if (!dark_mode && blend > 0) blend <= blend - 9'd4; // 64 个样本完成平滑切换
            if (result > 18'sd32767) sample_out <= 16'sd32767;
            else if (result < -18'sd32768) sample_out <= -16'sd32768;
            else sample_out <= result[15:0];
        end
    end
endmodule
