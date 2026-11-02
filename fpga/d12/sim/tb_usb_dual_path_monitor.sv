`timescale 1ns/1ps
module tb_usb_dual_path_monitor;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=1;
    reg [1:0] u1=0,u2=0;
    wire dp,dm,dp2,dm2;
    assign (pull1,pull0) dp=u1[1];
    assign (pull1,pull0) dm=u1[0];
    assign (pull1,pull0) dp2=u2[1]; // D6：设备侧驱动USB2，检查高阻接收路径。
    assign (pull1,pull0) dm2=u2[0];
    pressure_piano_28_touch_top #(.BOOT_CYCLES(10)) dut(.sd_miso(1'b1),.sys_clk(clk),.rst_n(rst_n),
        .enc_a(1'b1),.enc_b(1'b1),.dark_button_n(1'b1),.adc_miso(4'd0),
        .usb1_dp(dp),.usb1_dm(dm),.usb2_dp(dp2),.usb2_dm(dm2));
    integer a,b,n,checked=0;
    task check_view;
        begin
            // 原始引脚到50MHz同步器、完整快照握手、30MHz消隐换入，检查实际渲染器输入。
            wait(dut.u_system.frame_tick);repeat(10) @(posedge dut.u_system.pixel_clk);#1;
            if(dut.u_system.pixel_diag[70:69]!=={u1[0],u1[1]} || dut.u_system.pixel_diag[13:12]!==u2)
                $fatal(1,"Dual path pixel CDC lost bits u1=%b u2=%b got=%h",u1,u2,dut.u_system.pixel_diag);
            if(dut.u_system.media_video.u_renderer.diag_char(0,42,dut.u_system.pixel_diag)!==("0"+u1[1]) ||
               dut.u_system.media_video.u_renderer.diag_char(0,43,dut.u_system.pixel_diag)!==("0"+u1[0]) ||
               dut.u_system.media_video.u_renderer.diag_char(0,50,dut.u_system.pixel_diag)!==("0"+u2[1]) ||
               dut.u_system.media_video.u_renderer.diag_char(0,51,dut.u_system.pixel_diag)!==("0"+u2[0]))
                $fatal(1,"USB path displayed D+/D- order wrong");
            checked++;
        end
    endtask
    initial begin
        #10000;
        for(a=0;a<4;a++) for(b=0;b<4;b++) begin
            @(negedge clk);u1=a;u2=b;
            repeat(10) @(posedge clk);#1;
            if(dut.usb_armed || dut.usb_drive || dut.host_rst_n) $fatal(1,"Passive monitor unexpectedly enabled host");
            if({dp,dm}!==u1 || {dut.usb2_dp_rx,dut.usb2_dm_rx}!==u2 || dut.usb2_seen!==u2) $fatal(1,"Raw pin readback mismatch");
            if({dut.usb_diagnostic[69],dut.usb_diagnostic[70]}!==u1 || dut.usb_diagnostic[13:12]!==u2)
                $fatal(1,"Diagnostic packing mismatch");
            // 测试中缩短视频帧间隔，只加速已有时序计数器，不替换真实CDC/渲染器。
            repeat(3) begin
                @(negedge dut.u_system.pixel_clk);force dut.u_system.u_timing.x=0;force dut.u_system.u_timing.y=480;
                repeat(3) @(posedge dut.u_system.pixel_clk);
                @(negedge dut.u_system.pixel_clk);release dut.u_system.u_timing.x;release dut.u_system.u_timing.y;
                repeat(100) @(posedge dut.u_system.pixel_clk);
            end
            if({dut.u_system.pixel_diag[69],dut.u_system.pixel_diag[70]}!==u1 || dut.u_system.pixel_diag[13:12]!==u2)
                $fatal(1,"Two-clock snapshot mismatch");
            if(dut.u_system.media_video.u_renderer.diag_char(0,42,dut.u_system.pixel_diag)!==("0"+u1[1]) ||
               dut.u_system.media_video.u_renderer.diag_char(0,43,dut.u_system.pixel_diag)!==("0"+u1[0]) ||
               dut.u_system.media_video.u_renderer.diag_char(0,50,dut.u_system.pixel_diag)!==("0"+u2[1]) ||
               dut.u_system.media_video.u_renderer.diag_char(0,51,dut.u_system.pixel_diag)!==("0"+u2[0])) $fatal(1,"Rendered character mismatch");
            checked++;
        end
        $display("PASS usb_dual_path_monitor: all %0d USB1/USB2 raw combinations through explicit pad wrapper, 50MHz sync, 72bit CDC and real renderer characters; host remains reset/high-Z",checked);$finish;
    end
    initial begin #1000000;$fatal(1,"Dual path test timeout");end
endmodule
