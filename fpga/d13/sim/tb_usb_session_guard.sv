`timescale 1ns/1ps
module tb_usb_session_guard;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,button_n=0,lock=0,beat=0,run_beat=1;
    always #60 if(run_beat) beat=~beat;
    wire armed,healthy,fault;
    usb_session_guard #(.ARM_CYCLES(8),.WATCHDOG_CYCLES(30)) dut(clk,rst_n,button_n,lock,beat,armed,healthy,fault);
    task cycles(input integer n);repeat(n) begin @(posedge clk);#1;end endtask
    task release_key;begin @(negedge clk);button_n=1;cycles(8);end endtask
    task hold_key;begin @(negedge clk);button_n=0;cycles(15);end endtask
    initial begin
        #31;rst_n=1;lock=1;cycles(60);
        if(!healthy || armed) $fatal(1,"Boot-held button must not arm");
        release_key();button_n=0;cycles(3);release_key();
        if(armed) $fatal(1,"Short key press must not arm");
        hold_key();if(!armed) $fatal(1,"Long hold did not arm");
        cycles(100);if(!armed) $fatal(1,"Held key toggled more than once");
        release_key();hold_key();if(armed) $fatal(1,"Second long hold did not stop USB");
        release_key();hold_key();if(!armed) $fatal(1,"USB re-arm failed");
        lock=0;cycles(8);if(armed || !fault) $fatal(1,"Lock loss did not stop USB");
        lock=1;release_key();cycles(30);if(armed || !healthy) $fatal(1,"Unexpected automatic restart");
        hold_key();if(!armed || fault) $fatal(1,"Manual recovery failed");
        run_beat=0;cycles(40);if(armed || healthy || !fault) $fatal(1,"Clock-stopped-but-locked watchdog failed");
        run_beat=1;release_key();cycles(30);if(armed) $fatal(1,"Watchdog recovery must remain passive");
        hold_key();if(!armed || fault) $fatal(1,"Watchdog manual re-arm failed");
        rst_n=0;#1;if(armed) $fatal(1,"Reset must withdraw permission asynchronously");
        $display("PASS usb_session_guard: passive boot, held-at-boot/short press, single toggle, lock loss, stopped-clock watchdog, explicit recovery, reset");$finish;
    end
endmodule
