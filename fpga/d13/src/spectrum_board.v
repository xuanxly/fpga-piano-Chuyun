`timescale 1ns/1ps
module spectrum_dvi (
    input wire rst_n, serial_clk, pixel_clk, hs,vs,de,
    input wire [23:0] rgb,
    output wire clk_p,clk_n, output wire [2:0] data_p,data_n
);
`ifdef PIANO_XSIM
    // 只用于整机逻辑仿真，不声称校验了 TMDS 编码、串行电气或真实 PLL。
    assign clk_p=pixel_clk; assign clk_n=~pixel_clk;
    assign data_p={3{de}} & {rgb[23],rgb[15],rgb[7]}; assign data_n=~data_p;
`else
    DVI_TX_Top u_tx(.I_rst_n(rst_n),.I_serial_clk(serial_clk),.I_rgb_clk(pixel_clk),
        .I_rgb_vs(vs),.I_rgb_hs(hs),.I_rgb_de(de),.I_rgb_r(rgb[23:16]),.I_rgb_g(rgb[15:8]),.I_rgb_b(rgb[7:0]),
        .O_tmds_clk_p(clk_p),.O_tmds_clk_n(clk_n),.O_tmds_data_p(data_p),.O_tmds_data_n(data_n));
`endif
endmodule

`ifdef PIANO_XSIM
module spectrum_pll(input wire clkin,output reg clkout0=0,output reg clkout1=0,output reg lock=0);
    always #3.333333333 clkout0=~clkout0;          // 150 MHz 行为时钟，仅用于逻辑仿真
    always #16.666666667 clkout1=~clkout1;         // 30 MHz 像素时钟
    initial begin #200; lock=1; end
endmodule
`endif
