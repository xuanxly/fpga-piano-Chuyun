`timescale 1ns/1ps
// 验证新音色确实经过原来的录音/主音量/文件独占链路，而非只改变界面标签。
module tb_timbre_audio;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0;reg [27:0] touch_keys=1;reg [2:0] timbre_select=0;reg [6:0] volume_percent=100;
 reg playback_exclusive=0;wire record_valid,monitor_valid;wire signed [15:0] record_pcm,monitor_pcm;wire [2:0] fault;
 piano28_core #(.ENABLE_TOUCH(1),.ENABLE_MEDIA(1),.ENABLE_TIMBRE(1),.AMP_STARTUP_CYCLES(10)) dut(
  .sys_clk(clk),.rst_n(rst_n),.adc_miso(4'd0),.enc_a(1'b1),.enc_b(1'b1),.dark_button_n(1'b1),
  .touch_keys(touch_keys),.timbre_select(timbre_select),.volume_percent(volume_percent),
  .transpose_set_valid(1'b0),.transpose_set(4'sd0),.playback_exclusive(playback_exclusive),
  .playback_l(16'sd12345),.playback_r(-16'sd23456),.record_valid(record_valid),.record_pcm(record_pcm),
  .monitor_valid(monitor_valid),.monitor_pcm(monitor_pcm),.fault(fault));
 integer records=0,dacs=0,nz=0,p,k;reg [31:0] sums[0:4];
 always @(negedge clk)if(rst_n)begin
  if(record_valid)records=records+1;if(monitor_valid)dacs=dacs+1;
  if(fault)$fatal(1,"core audio fault %b",fault);
 end
 task samples(input integer count);begin repeat(count)begin @(posedge record_valid);@(negedge clk);end end endtask
 initial begin
  #100;rst_n=1;
  for(p=0;p<5;p=p+1)begin
   timbre_select=p;touch_keys=0;samples(270);touch_keys=1;sums[p]=0;nz=0;
   repeat(1024)begin samples(1);sums[p]=sums[p]+record_pcm;if(record_pcm!=0)nz=nz+1;end
   if(nz<900)$fatal(1,"new audio path silent %0d",p);
   for(k=0;k<p;k=k+1)if(sums[k]==sums[p])$fatal(1,"recorded timbres identical");
  end
  volume_percent=0;samples(1024);if(monitor_pcm!=0||record_pcm==0)$fatal(1,"volume0 must preserve recording only");
  volume_percent=100;playback_exclusive=1;samples(1024);
  if(monitor_pcm!=12345||record_pcm==12345)$fatal(1,"file playback not exclusive/record changed");
  timbre_select=1;samples(300);if(monitor_pcm!=12345)$fatal(1,"timbre affected file playback");
  playback_exclusive=0;touch_keys=0;samples(16);touch_keys=1;samples(512);if(record_pcm==0)$fatal(1,"return to instrument");
  if(records<8500||dacs-records>2||records-dacs>2)$fatal(1,"recording dropped frames %0d/%0d",records,dacs);
  $display("PASS timbre_audio: all5 in internal recording, volume0 record, independent file playback, continuous %0d record frames/%0d DAC frames",records,dacs);$finish;
 end
 initial begin #350000000;$fatal(1,"audio timeout");end
endmodule
