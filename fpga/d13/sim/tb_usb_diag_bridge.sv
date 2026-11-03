`timescale 1ns/1ps
module tb_usb_diag_bridge;
    reg usb_clk=0,sys_clk=0,run_usb=1;
    always #8.333333 if(run_usb) usb_clk=~usb_clk;
    always #10 sys_clk=~sys_clk;
    reg usb_rst_n=0,sys_rst_n=0,usb_lock=0,report_error=0;
    reg [31:0] tag=0;wire [63:0] info={tag,~tag};wire [71:0] diagnostic;
    usb_diag_bridge #(.STALE_CYCLES(40)) dut(usb_clk,usb_rst_n,info,usb_lock,report_error,sys_clk,sys_rst_n,diagnostic);
    always @(posedge usb_clk) if(usb_rst_n) tag<=tag+1;
    integer coherent=0;
    always @(posedge sys_clk) begin
        #1;if(sys_rst_n && dut.valid) begin
            if(diagnostic[63:32]!==~diagnostic[31:0]) $fatal(1,"Torn USB diagnostic CDC word %h",diagnostic);
            coherent++;
        end
    end
    initial begin
        #101;sys_rst_n=1;usb_rst_n=1;usb_lock=1;
        #5000;
        if(diagnostic[66:64]!==3'b111 || coherent<10) $fatal(1,"USB clock/reset/lock status missing %h",diagnostic);
        report_error=1;#100;if(!diagnostic[67]) $fatal(1,"Report error not synchronized");
        run_usb=0;#2000;
        if(diagnostic[64] || !diagnostic[65]) $fatal(1,"Stopped clock not distinguished from PLL lock");
        usb_rst_n=0;usb_lock=0;#200;if(diagnostic[66:65]!=0) $fatal(1,"Reset/lock status stale");
        usb_rst_n=1;usb_lock=1;run_usb=1;#3000;
        if(diagnostic[66:64]!==3'b111) $fatal(1,"Diagnostic did not recover after clock/reset restart");
        $display("PASS usb_diag_bridge: %0d coherent CDC snapshots; clock stopped/locked, reset, error, restart distinguished",coherent);$finish;
    end
endmodule
