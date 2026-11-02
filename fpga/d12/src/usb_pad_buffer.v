`timescale 1ns/1ps
// 高云Arora V显式双向IO：OEN=1时高阻接收，OEN=0时输出I。
// 独立rx信号来自芯片引脚，不使用内部待发送数据代替引脚输入。
module usb_pad_buffer(
    inout wire pad,input wire tx,input wire drive,output wire rx
);
`ifdef PIANO_XSIM
    assign pad=drive?tx:1'bz; // 与厂商IOBUF的OEN极性一致；不模拟模拟门限/ESD。
    assign rx=pad;
`else
    IOBUF u_pad(.IO(pad),.I(tx),.OEN(~drive),.O(rx));
`endif
endmodule
