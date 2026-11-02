`timescale 1ns/1ps
module debounce_bit #(
    parameter integer STABLE_CYCLES = 250000,
    parameter RESET_LEVEL = 1'b1
)(
    input wire clk, input wire rst_n,
    input wire async_in,              // 外部机械触点信号
    output reg stable_out             // 同步并消抖后的稳定电平
);
    reg [1:0] sync_ff;
    reg [31:0] count;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_ff <= {2{RESET_LEVEL}};
            stable_out <= RESET_LEVEL;
            count <= 0;
        end else begin
            sync_ff <= {sync_ff[0], async_in}; // 两级同步，降低亚稳态传播概率
            if (sync_ff[1] == stable_out) count <= 0;
            else if (count >= STABLE_CYCLES - 1) begin
                stable_out <= sync_ff[1];     // 连续稳定足够长才接受新电平
                count <= 0;
            end else count <= count + 1'b1;
        end
    end
endmodule
