`timescale 1ns/1ps

module piano_osc (
    input  wire clk,                    // FPGA 系统时钟
    input  wire rst_n,                  // 低电平复位
    input  wire sample_tick,            // 每个音频采样点更新一次
    input  wire note_start,             // 新音符开始脉冲，持续变调时不触发
    input  wire [31:0] phase_step,       // 相位增量，决定音符频率
    output reg signed [15:0] sample_out // 输出 16 位有符号波形
);

    reg [31:0] phase_acc;               // 相位累加器，溢出后自然回绕

    function [15:0] quarter_sine;       // 保存四分之一周期的正弦数学表
        input [4:0] addr;
        begin
            case (addr)
                5'd0:  quarter_sine = 16'd0;
                5'd1:  quarter_sine = 16'd3212;
                5'd2:  quarter_sine = 16'd6393;
                5'd3:  quarter_sine = 16'd9512;
                5'd4:  quarter_sine = 16'd12539;
                5'd5:  quarter_sine = 16'd15446;
                5'd6:  quarter_sine = 16'd18204;
                5'd7:  quarter_sine = 16'd20787;
                5'd8:  quarter_sine = 16'd23170;
                5'd9:  quarter_sine = 16'd25329;
                5'd10: quarter_sine = 16'd27245;
                5'd11: quarter_sine = 16'd28898;
                5'd12: quarter_sine = 16'd30273;
                5'd13: quarter_sine = 16'd31356;
                5'd14: quarter_sine = 16'd32137;
                5'd15: quarter_sine = 16'd32609;
                5'd16: quarter_sine = 16'd32767;
                default: quarter_sine = 16'd32767;
            endcase
        end
    endfunction

    function signed [15:0] sine16;      // 利用对称性计算整个正弦周期
        input [31:0] phase;
        reg [14:0] pos;
        reg [4:0] addr;
        reg [15:0] y0, y1;
        reg [25:0] interp;
        reg [15:0] magnitude;
        begin
            if (phase[30])
                pos = 15'd16384 - {1'b0, phase[29:16]}; // 第二、第四象限镜像
            else
                pos = {1'b0, phase[29:16]};            // 第一、第三象限直接取位置

            addr = pos[14:10];                        // 相邻表项的起始地址
            y0 = quarter_sine(addr);                  // 前一个表项
            y1 = quarter_sine(addr + 5'd1);           // 后一个表项

            interp = (y1 - y0) * pos[9:0];            // 计算两个表项之间的增量
            magnitude = y0 + interp[25:10];           // 线性插值，减少波形台阶

            if (phase[31])
                sine16 = (~magnitude) + 16'd1;        // 下半周期输出负数补码
            else
                sine16 = magnitude;                  // 上半周期输出正数
        end
    endfunction

    wire [31:0] phase_2 =
        {phase_acc[30:0], 1'b0};                      // 二倍相位，对应二次泛音

    wire [31:0] phase_3 =
        phase_acc + phase_2;                         // 三倍相位，对应三次泛音

    reg signed [15:0] fundamental;                  // 基音的插值结果先寄存
    reg signed [15:0] harmonic_2;                   // 二次泛音单独寄存
    reg signed [15:0] harmonic_3;                   // 三次泛音单独寄存
    reg [31:0] sine_phase_1, sine_phase_2, sine_phase_3; // 相位运算也单独寄存，不和插值乘法串联
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sine_phase_1<=0; sine_phase_2<=0; sine_phase_3<=0;
            fundamental<=0; harmonic_2<=0; harmonic_3<=0;
        end
        else begin
            sine_phase_1<=phase_acc; sine_phase_2<=phase_2; sine_phase_3<=phase_3;
            fundamental<=sine16(sine_phase_1);      // 两个音频节拍之间连续准备，隔开查表乘法与混音
            harmonic_2<=sine16(sine_phase_2);
            harmonic_3<=sine16(sine_phase_3);        // 50 MHz / 48 kHz 下计算时间远小于一帧
        end
    end

    wire signed [17:0] f_ext =
        {{2{fundamental[15]}}, fundamental};         // 符号扩展，保持正负号

    wire signed [17:0] h2_ext =
        {{2{harmonic_2[15]}}, harmonic_2};            // 扩位后参与混合

    wire signed [17:0] h3_ext =
        {{2{harmonic_3[15]}}, harmonic_3};            // 扩位后参与混合

    wire signed [17:0] wave_mix =
        (f_ext >>> 1) +                              // 基音幅度乘以 1/2
        (h2_ext >>> 3) +                             // 二次泛音幅度乘以 1/8
        (h3_ext >>> 4);                              // 三次泛音幅度乘以 1/16

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_acc <= 32'd0;                      // 复位时清零相位
            sample_out <= 16'sd0;                    // 复位时输出零
        end else if (note_start) begin
            phase_acc <= 32'd0;                      // 新音符从零相位开始
            sample_out <= 16'sd0;
        end else if (sample_tick) begin
            phase_acc <= phase_acc + phase_step;     // 每个采样点推进相位
            sample_out <= wave_mix[15:0];            // 混合结果已留出幅度余量
        end
    end

endmodule
