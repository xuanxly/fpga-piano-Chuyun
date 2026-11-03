`timescale 1ns/1ps
module tb_usb_guarded_startup;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=1,button_n=1,attached=1;
    tri dp,dm;
    assign (weak1,weak0) dp=1'b0; // 板上15k主机下拉，比设备1.5k上拉弱。
    assign (weak1,weak0) dm=1'b0;
    assign (pull1,highz0) dp=attached?1'b1:1'bz;
    pressure_piano_28_touch_top #(.BOOT_CYCLES(10),.USB_ARM_CYCLES(8),.USB_WATCHDOG_CYCLES(2000),
        .USB_ATTACH_CYCLES(60),.USB_RESET_CYCLES(30000),.USB_RECOVERY_CYCLES(60)) dut(
        .sd_miso(1'b1),.sys_clk(clk),.rst_n(rst_n),.enc_a(1'b1),.enc_b(1'b1),.dark_button_n(button_n),.adc_miso(4'd0),.usb1_dp(1'b0),.usb1_dm(1'b0),.usb2_dp(dp),.usb2_dm(dm));
    integer driven=0,sys_edges=0;
    always @(posedge clk) begin sys_edges++;if(dut.usb_drive) driven++;end
    initial begin
        // 配置时已接TOUCH：输入有J，但默认主机必须保持复位、输出高阻。
        #20000;
        if(!dut.u_system.sys_reset_n || !dut.usb_healthy || dut.usb_armed || dut.usb_drive || {dp,dm}!==2'b10)
            $fatal(1,"Passive cold start/preconnected device failed reset=%b healthy=%b armed=%b drive=%b lines=%b guard=%b",dut.u_system.sys_reset_n,dut.usb_healthy,dut.usb_armed,dut.usb_drive,{dp,dm},dut.u_guard.age);
        if(dut.usb_diagnostic[70:69]!==2'b00 || dut.usb_diagnostic[13:12]!==2'b10) $fatal(1,"USB2 J / inactive USB1 raw monitors failed");
        attached=0;#20000;if({dp,dm}!==0 || dut.usb_drive) $fatal(1,"Passive detach failed");
        attached=1;#20000;if({dp,dm}!==2'b10 || dut.usb_drive || driven!=0) $fatal(1,"Passive hotplug drove USB");
        button_n=0;#1000;button_n=1;
        wait(dut.usb_drive);#100;
        if({dp,dm}!==0) $fatal(1,"Enabled host bus reset missing");
        force dut.u_usb_pll.run_clock=0; // 注入：时钟停止，LOCK仍为1。
        #100000;
        if(dut.usb_drive || dut.usb_armed || !dut.usb_watchdog_fault || dut.touch_connected || {dp,dm}!==2'b10)
            $fatal(1,"Stopped-clock output/touch release failed");
        if(!dut.u_system.sys_reset_n || sys_edges<7000) $fatal(1,"USB fault reset the piano/display system");
        release dut.u_usb_pll.run_clock;dut.u_usb_pll.run_clock=1;#20000;
        if(dut.usb_armed || dut.usb_drive) $fatal(1,"USB restarted without operator after watchdog");
        $display("PASS usb_guarded_startup: no external reset, preplug/hotplug high-Z, raw D+/D-, manual start, LOCK-stuck clock-stop withdraws drive and touch, piano remains running");$finish;
    end
    initial begin #1000000;$fatal(1,"Guarded startup timeout");end
endmodule
