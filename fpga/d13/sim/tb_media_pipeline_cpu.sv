`timescale 1ns/1ps
module tb_media_pipeline_cpu;
 reg clk=0,rst_n=0;always #10 clk=~clk;
 integer phase=0;reg sample_tick=0;wire [31:0] boot;wire [2175:0] ui;
 wire signed [15:0] l,r;integer heard=0,nonzero=0;integer minimum=6144;
 always @(posedge clk)if(rst_n)begin
  if(phase==1041)begin phase<=0;sample_tick<=1;end else begin phase<=phase+1;sample_tick<=0;end
  if(dut.play_enable&&sample_tick&&!dut.play_pause)begin heard++;if(heard%4000==0)$display("Pipeline heard=%0d FIFO=%0d",heard,dut.fifo_count);if(l||r)nonzero++;if(dut.fifo_count<minimum)minimum=dut.fifo_count;end
 end
 media_soc #(.FIRMWARE("media_pipeline.hex")) dut(.clk(clk),.rst_n(rst_n),.page(4'd5),.command_valid(1'b0),.command(32'd0),.record_valid(1'b0),.record_pcm(16'd0),.sample_tick(sample_tick),.sd_miso(1'b1),.ui_snapshot(ui),.boot_status(boot),.play_l(l),.play_r(r),.pixel_clk(clk),.display_bank(ui[0]),.text_address(6'd0));
 initial begin #101;rst_n=1;wait(boot==32'hd9b1d00d||boot[31:8]==24'hd9b1ee);#1;
  if(boot!=32'hd9b1d00d)$fatal(1,"playback pipeline failed status=%h heard=%0d fifo=%0d",boot,heard,dut.fifo_count);
  if(heard<24000||nonzero<20000||dut.play_underflow)$fatal(1,"insufficient full-rate playback");
  $display("PASS media_pipeline_cpu: actual C scheduler + twenty MP3 frames + 44.1k-to-48k resampling + stereo FIFO consumption at realtime; heard=%0d nonzero=%0d minimum=%0d",heard,nonzero,minimum);$finish;
 end
 initial begin #1200000000;$fatal(1,"playback pipeline timeout boot=%h fifo=%0d heard=%0d",boot,dut.fifo_count,heard);end
endmodule
