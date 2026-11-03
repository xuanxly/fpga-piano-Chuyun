`timescale 1ns/1ps
// MCP3008 单端输入、SPI 模式 0、24 个时钟一笔；协议见 docs/HARDWARE.md。
module mcp3008_scan #(
    parameter integer CLK_HZ = 50000000,     // 首版系统时钟 50 MHz
    parameter integer SPI_HZ = 500000,       // 3.3 V 下先采用保守的 500 kHz
    parameter integer KEY_UPDATE_HZ = 1000   // CH0～CH6 各约每 1 ms 更新一次
)(
    input wire clk, input wire rst_n,        // 统一系统时钟域，低有效复位
    input wire adc_miso,                     // ADC 的 DOUT
    output reg adc_cs_n,                     // ADC 的 CS，低有效
    output reg adc_sck,                      // 空闲为低，上升沿采样
    output reg adc_mosi,                     // ADC 的 DIN，下降沿更新
    output reg raw_valid,                    // 样本有效脉冲，仅一个系统时钟
    output reg [2:0] raw_channel,            // 样本所属的通道：0～6
    output reg [9:0] raw_sample              // MCP3008 的十位结果：0～1023
);
    localparam integer HALF_CYCLES = CLK_HZ / (2 * SPI_HZ); // SPI 半周期计数
    localparam integer SLOT_CYCLES = CLK_HZ / (7 * KEY_UPDATE_HZ); // 七路均匀轮询
    reg [31:0] slot_count, half_count;       // 轮询节拍与 SPI 分频
    reg [2:0] channel;                      // 当前转换通道
    reg [4:0] bit_index;                    // 24 位事务的位序号：0～23
    reg [23:0] tx_shift;                    // 命令移位寄存器
    reg [9:0] rx_shift;                     // 最后十个接收位才是有效结果
    reg busy;                              // 当前是否正在通信
    reg [1:0] miso_sync;                    // 两级同步，半个 SPI 周期留出等待时间
    wire [23:0] command = {7'd0, 1'b1, 1'b1, channel, 12'd0}; // 01h、(8+通道)<<4、00h

    // synthesis translate_off
    initial begin                          // 参数错误在仿真开始时指出
        if (HALF_CYCLES < 4 || SPI_HZ > 1350000 || SPI_HZ < 10000)
            $fatal(1, "MCP3008 SPI divider/rate outside supported range");
        if (SLOT_CYCLES <= 48 * HALF_CYCLES + 2)
            $fatal(1, "MCP3008 polling slot shorter than one transaction");
    end
    // synthesis translate_on

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            slot_count <= 0; half_count <= 0; channel <= 0; bit_index <= 0;
            tx_shift <= 0; rx_shift <= 0; busy <= 0; miso_sync <= 0;
            adc_cs_n <= 1; adc_sck <= 0; adc_mosi <= 0; // 复位时停止通信
            raw_valid <= 0; raw_channel <= 0; raw_sample <= 0;
        end else begin
            miso_sync <= {miso_sync[0], adc_miso}; // 不代替实际板级时序核验
            raw_valid <= 0;
            if (slot_count == SLOT_CYCLES - 1) slot_count <= 0;
            else slot_count <= slot_count + 1'b1;
            if (!busy) begin
                if (slot_count == 0) begin
                    busy <= 1; adc_cs_n <= 0; adc_sck <= 0;
                    half_count <= 0; bit_index <= 0; rx_shift <= 0;
                    tx_shift <= command; adc_mosi <= command[23]; // 先建立 CS 与数据，再产生第一沿
                end
            end else if (half_count == HALF_CYCLES - 1) begin
                half_count <= 0;
                if (!adc_sck) begin
                    adc_sck <= 1;
                    rx_shift <= {rx_shift[8:0], miso_sync[1]}; // 第 15～24 个上升沿接收 B9～B0
                end else begin
                    adc_sck <= 0;
                    if (bit_index == 23) begin
                        adc_cs_n <= 1; busy <= 0; adc_mosi <= 0;
                        raw_sample <= rx_shift; raw_channel <= channel; raw_valid <= 1; // 十位齐全后才发布
                        if (channel == 6) channel <= 0;
                        else channel <= channel + 1'b1; // CH7 留作后续扩展
                    end else begin
                        bit_index <= bit_index + 1'b1;
                        tx_shift <= {tx_shift[22:0], 1'b0};
                        adc_mosi <= tx_shift[22];        // 下降沿更新命令，满足建立时间
                    end
                end
            end else half_count <= half_count + 1'b1;
        end
    end
endmodule
