`timescale 1ns/1ps
module reset_sync (
    input wire clk,                   // 系统时钟
    input wire ext_rst_n,             // 外部低有效复位
    output wire rst_n                 // 异步进入复位，同步退出复位
);
    reg [1:0] pipe;
    always @(posedge clk or negedge ext_rst_n) begin
        if (!ext_rst_n) pipe <= 2'b00; // 按下复位立即清零
        else pipe <= {pipe[0], 1'b1};  // 两级触发器保证复位释放在时钟边沿发生
    end
    assign rst_n = pipe[1];
endmodule
