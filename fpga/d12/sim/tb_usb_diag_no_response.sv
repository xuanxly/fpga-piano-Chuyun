`timescale 1ns/1ps
// 设备拉高D+但完全不应答：验证真实故障入口的超时、失败位置保留和重试计数。
module tb_usb_diag_no_response;
    reg clk=0;always #8.333333 clk=~clk;reg rst_n=0,attached=0;
    wire dp,dm,po,mo,oe,connected,valid;wire [87:0] data;
    wire [3:0] fault;wire [7:0] state;wire [63:0] diagnostic;
    assign (weak1,weak0) dp=attached;
    assign (weak1,weak0) dm=1'b0;
    assign dp=oe?po:1'bz;assign dm=oe?mo:1'bz;
    ws170120_usb_host #(.ATTACH_CYCLES(100),.RESET_CYCLES(100),.RECOVERY_CYCLES(100)) dut(
        clk,rst_n,dp,dm,po,mo,oe,connected,valid,data,fault,state,diagnostic);
    initial begin
        #201;rst_n=1;#5000;
        if(state!=0 || diagnostic[62:60]!=0 || connected) $fatal(1,"Phantom device on empty USB port");
        attached=1;
        wait(diagnostic[59:52]==1);#100;
        if(diagnostic[31:28]!=2 || diagnostic[23:16]!=11 || diagnostic[27:24]!=0 || diagnostic[35:32]!=3 ||
           diagnostic[62:60]!=3'b011 || diagnostic[51:44]!=0 || connected)
            $fatal(1,"No-response diagnostic not preserved: %h",diagnostic);
        // 后续重试仍保留原故障上下文；不能每次重试清零ERR，让实屏看起来没有错误。
        #2000000;
        if(diagnostic[31:16]!=16'h200b || diagnostic[35:32]!=3) $fatal(1,"Retry overwrote failure evidence %h",diagnostic);
        $display("PASS usb_diag_no_response: empty port stays detached; attached silent device -> ERR2 AT0B P0 TR3, no reports, failure context survives retries");
        $finish;
    end
    initial begin #180000000;$fatal(1,"No-response test timeout state=%d fault=%d",state,fault);end
endmodule
