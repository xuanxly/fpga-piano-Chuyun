`timescale 1ns/1ps

module pt8211_tx #(
    parameter integer CLK_HZ    = 50000000, // 板卡系统时钟
    parameter integer SAMPLE_HZ = 48000     // 固定 48 kHz 音频采样率
)(
    input  wire clk,
    input  wire rst_n,

    input  wire signed [15:0] sample_l,
    input  wire signed [15:0] sample_r,

    output reg sample_tick,
    output reg dac_bck,
    output reg dac_ws,
    output reg dac_din
);

    localparam integer EDGE_HZ = SAMPLE_HZ * 64; // 一帧 32 位，每位两个 BCK 边沿

    reg  [31:0] phase_acc; // 分数分频累加器，平均帧率准确到 48 kHz
    wire [32:0] phase_sum =
        {1'b0, phase_acc} + EDGE_HZ;
    wire [32:0] phase_reduced =
        phase_sum - CLK_HZ;

    reg [31:0] shift_reg;
    reg [4:0]  bit_index;
    reg        started;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_acc   <= 0;
            shift_reg   <= 0;
            bit_index   <= 0;
            started     <= 0;
            sample_tick <= 0;
            dac_bck     <= 0;
            dac_ws      <= 0;
            dac_din     <= 0;
        end
        else begin
            sample_tick <= 0;

            if (!started) begin
                started     <= 1;
                sample_tick <= 1; // 本帧已捕获，声音核心计算下一帧
                dac_din     <= sample_r[15]; // WS=0 先发送右声道的最高位
                shift_reg   <=
                    {sample_r[14:0], sample_l, 1'b0};

            end else if (phase_sum >= CLK_HZ) begin
                phase_acc <= phase_reduced[31:0];
                dac_bck   <= ~dac_bck;

                if (dac_bck) begin // 当前为高，下一状态是下降沿，在此更新 DIN 和 WS
                    if (bit_index == 31) begin
                        bit_index   <= 0;
                        dac_ws      <= 0;
                        dac_din     <= sample_r[15]; // WS=0 先发送右声道的最高位
                        shift_reg   <=
                            {sample_r[14:0], sample_l, 1'b0};
                        sample_tick <= 1; // 本帧已捕获，声音核心计算下一帧
                    end else begin
                        bit_index <= bit_index + 1'b1;
                        dac_din   <= shift_reg[31]; // 按最高位优先发送
                        shift_reg <=
                            {shift_reg[30:0], 1'b0};

                        if (bit_index == 15)
                            dac_ws <= 1; // 后十六位为左声道，没有标准 I2S 的一位延迟
                    end
                end
            end else begin
                phase_acc <= phase_sum[31:0];
            end
        end
    end

endmodule