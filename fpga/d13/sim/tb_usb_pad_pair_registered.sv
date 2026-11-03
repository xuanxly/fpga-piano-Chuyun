`timescale 1ns/1ps
// 独立编译厂商IOBUF分支：无时钟启动、数据/使能同拍、异步关闭和停时钟保护。
module tb_usb_pad_pair_registered;
    reg clk=0,run_clock=0,allow=1,enable=1,dp_tx=1,dm_tx=0;
    always #5 if(run_clock) clk=~clk;
    tri dp,dm;wire dp_rx,dm_rx,drive;
    assign (weak1,weak0) dp=1'b0;
    assign (weak1,weak0) dm=1'b0;
    usb_pad_pair_registered dut(clk,allow,enable,dp_tx,dm_tx,dp,dm,dp_rx,dm_rx,drive);
    integer k;
    initial begin
        #100;
        if(drive!==0 || {dp,dm}!==0 || dut.pad_oe_n!==1) $fatal(1,"Unclocked INIT must disable both pads");
        allow=0;run_clock=1;
        #20;
        for(k=0;k<8;k++) begin
            @(negedge clk);allow=1;{enable,dp_tx,dm_tx}=k;#1;
            if(drive!==0) $fatal(1,"Enable changed before a clock edge");
            @(posedge clk);#1;
            if(drive!==enable || {dp,dm}!==(enable?{dp_tx,dm_tx}:2'b00) || {dp_rx,dm_rx}!=={dp,dm})
                $fatal(1,"Registered pair data/OEN alignment failed %b",k[2:0]);
            #1;allow=0;#1;
            if(drive!==0 || {dp,dm}!==0) $fatal(1,"Asynchronous disable waited for a clock");
        end
        @(negedge clk);allow=1;enable=1;dp_tx=1;dm_tx=0;
        @(posedge clk);#1;if({dp,dm}!==2'b10 || drive!==1) $fatal(1,"Cannot enter transmit");
        run_clock=0;#30;allow=0;#1;
        if(drive!==0 || {dp,dm}!==0) $fatal(1,"Stopped clock prevented output withdrawal");
        $display("PASS usb_pad_pair_registered: no-clock INIT=high-Z, 8 data/OEN combinations clock-aligned, asynchronous release, clock-stop disable, native IOBUF readback");$finish;
    end
endmodule
