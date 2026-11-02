`timescale 1ns/1ps
// WS2812B-2020-V6 单线发送器：源帧在 busy 期间保持不变，按 D001→D112 发送 GRB。
module ws2812_frame_tx #(
    parameter integer CLK_HZ = 50000000,           // 系统时钟，默认 50MHz
    parameter integer LED_COUNT = 112            // 本灯板共有 112 个独立像素
)(
    input wire clk, rst_n,
    input wire start,                             // ready 时的单拍启动请求
    input wire [23:0] pixel_grb,                  // 源存储器的同步读出数据，G 在最高字节
    output reg [6:0] read_index,                  // 当前需要读取的灯号，0 对应 D001
    output wire ready, busy,
    output reg frame_done,                       // 数据发送和帧尾复位低电平都完成后脉冲
    output reg led_data                          // 接 FPGA AB20，经板上 HCT125 驱动灯链
);
    // 50MHz 下：0高16拍=320ns；1高32拍=640ns；位周期63拍=1260ns。
    // 每个像素装载额外留2拍低电平，最长0低电平为980ns，仍在V6范围内。
    localparam integer T0H = (CLK_HZ * 64'd320 + 999999999) / 1000000000;
    localparam integer T1H = (CLK_HZ * 64'd640 + 999999999) / 1000000000;
    localparam integer BIT_CYCLES = (CLK_HZ * 64'd1260 + 999999999) / 1000000000;
    localparam integer RESET_CYCLES = (CLK_HZ * 64'd320 + 999999) / 1000000; // 320µs，超过280µs
    localparam [1:0] RESET_LOW=0, IDLE=1, LOAD=2, SEND=3;
    reg [1:0] state;
    reg [31:0] cycle_count;                       // 同时服务位时序和帧间低电平计数
    reg [23:0] shift_word;                        // 只保存一颗灯的数据，不复制整条灯链
    reg [4:0] bit_left;                           // 当前字还需发送的位号：23..0
    reg report_done;                             // 上电低电平结束不算一帧发送完成
    wire [31:0] high_cycles = shift_word[23] ? T1H : T0H;
    assign ready = (state == IDLE);
    assign busy = !ready;

    // synthesis translate_off
    initial begin
        if (CLK_HZ != 50000000 || LED_COUNT < 1 || LED_COUNT > 128)
            $fatal(1,"WS2812 timing qualified for 50MHz and 1..128 pixels");
    end
    // synthesis translate_on

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=RESET_LOW; cycle_count<=0; shift_word<=0; bit_left<=23;
            read_index<=0; frame_done<=0; led_data<=0; report_done<=0;
        end else begin
            frame_done<=0;
            case (state)
                RESET_LOW: begin
                    led_data<=0;                  // 上电及每帧结束均强制足够长的低电平
                    if (cycle_count == RESET_CYCLES-1) begin
                        cycle_count<=0; state<=IDLE; frame_done<=report_done; report_done<=0;
                    end else cycle_count<=cycle_count+1'b1;
                end
                IDLE: begin
                    led_data<=0;
                    if (start) begin read_index<=0; cycle_count<=0; state<=LOAD; end
                end
                LOAD: begin
                    // 地址改变后等待两个时钟，兼容同步读存储器及其非阻塞赋值。
                    if (cycle_count == 1) begin
                        shift_word<=pixel_grb; bit_left<=23; cycle_count<=0; led_data<=1; state<=SEND;
                    end else cycle_count<=cycle_count+1'b1;
                end
                SEND: begin
                    if (cycle_count == high_cycles-1) led_data<=0;
                    if (cycle_count == BIT_CYCLES-1) begin
                        cycle_count<=0;
                        if (bit_left != 0) begin
                            shift_word<={shift_word[22:0],1'b0}; bit_left<=bit_left-1'b1; led_data<=1;
                        end else if (read_index == LED_COUNT-1) begin
                            led_data<=0; report_done<=1; state<=RESET_LOW;
                        end else begin
                            read_index<=read_index+1'b1; led_data<=0; state<=LOAD;
                        end
                    end else cycle_count<=cycle_count+1'b1;
                end
                default: begin state<=RESET_LOW; cycle_count<=0; led_data<=0; report_done<=0; end
            endcase
        end
    end
endmodule
