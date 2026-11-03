`timescale 1ns/1ps
// 跑实际D12 exFAT/WAV固件及40KiB ROM/24KiB RAM，不用替代固件冒充CPU已启动。
module tb_media_boot;
    reg clk=0;always #10 clk=~clk;reg rst_n=0;
    wire cs,sck,mosi,exclusive,nav;wire [2:0] nav_page;wire signed [15:0] l,r;
    wire [2175:0] ui;wire [31:0] boot;
    media_soc dut(.ch_ready(1'b0),.ch_rx_req(1'b0),.ch_tx_ack(1'b0),.ch_rx_data(4'd0),.keys(28'd0),
        .pixel_clk(clk),.display_bank(ui[0]),.text_address(6'd0),.clk(clk),.rst_n(rst_n),.page(4'd0),.command_valid(1'b0),.command(32'd0),
        .record_valid(1'b0),.record_pcm(16'sd0),.sample_tick(1'b0),.playback_exclusive(exclusive),.play_l(l),.play_r(r),
        .ui_snapshot(ui),.nav_valid(nav),.nav_page(nav_page),.sd_cs_n(cs),.sd_sck(sck),.sd_mosi(mosi),.sd_miso(1'b1),.boot_status(boot));
    integer edges=0;
    always @(posedge sck)if(rst_n)edges++;
    initial begin
        #101;rst_n=1;
        wait(boot==32'hd9000001);
        wait(ui[2069:2064]==1); // 状态栏真实固件发布NO CARD。
        wait(cs&&edges>=80);#10000;
        if(exclusive||l||r||dut.rec_enable||dut.play_enable||dut.event_overflow)$fatal(1,"boot enabled audio/record unexpectedly");
        $display("PASS media_boot: actual VexRiscv firmware initializes data/BSS, commits UI, clocks SD initialization, handles absent card; edges=%0d boot=%h",edges,boot);$finish;
    end
    initial begin #30000000;$fatal(1,"CPU firmware boot timeout boot=%h pc=%h ui=%h",boot,dut.u_cpu.IBusCachedPlugin_fetchPc_pc,ui[2079:2048]);end
endmodule
