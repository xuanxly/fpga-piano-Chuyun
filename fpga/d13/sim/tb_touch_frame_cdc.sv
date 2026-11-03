`timescale 1ns/1ps
module tb_touch_frame_cdc;
    reg sc=0,dc=0;always #8.333333 sc=~sc;always #10 dc=~dc;
    reg sr=0,dr=0,c=0,v=0;reg [4:0] a=0;reg [39:0] ids=0;reg [49:0] xs=0,ys=0;
    wire co,vo;wire [4:0] ao;wire [39:0] io;wire [49:0] xo,yo;
    touch_frame_cdc dut(sc,sr,c,v,a,ids,xs,ys,dc,dr,co,vo,ao,io,xo,yo);
    integer i,seen=0;
    always @(posedge dc) begin #1;if(vo && co) begin
        // 每帧四个字段都编码同一个数字，任何跨域撕裂都会被发现。
        if(io!==xo[39:0] || io!==yo[39:0] || ao!==io[4:0]) $fatal(1,"CDC torn frame");seen++;
    end end
    initial begin
        #101;sr=1;dr=1;c=1;
        for(i=1;i<=200;i++) begin
            @(negedge sc);v=1;a=i;ids=i;xs=i;ys=i;
            @(negedge sc);v=0;
            if(i%3==0) repeat(23) @(negedge sc);
        end
        #2000;if(!co || io!=200 || seen<60) $fatal(1,"latest frame lost");
        @(negedge sc);c=0;#2000;if(co || ao) $fatal(1,"disconnect not delivered");
        $display("PASS touch_frame_cdc: two asynchronous clocks, coherent snapshots, latest frame and disconnect, received=%0d",seen);$finish;
    end
endmodule
