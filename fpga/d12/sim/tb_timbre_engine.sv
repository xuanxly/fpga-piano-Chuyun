`timescale 1ns/1ps
// 行为验收：5种音色、28复音、移调极限、切换淡出/清声部/持键释放后重触发。
module tb_timbre_engine;
    wire vibrato_enable=0;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,sample_tick=0;reg [27:0] key_gate=0;reg [335:0] key_pressure={28{12'd4095}};
 reg signed [3:0] transpose=0;reg [2:0] timbre_select=0;
 wire signed [15:0] mixed_sample;wire frame_done;wire [27:0] voice_active;wire busy,ready,deadline_fault;
 piano28_timbre_engine dut(.*);
 integer frames=0,nonzero,cycles,k,p;reg signed [15:0] peak[0:4];reg [31:0] signatures[0:4];
 task frame;
 begin
  @(negedge clk);sample_tick=1;@(negedge clk);sample_tick=0;cycles=0;
  while(!frame_done)begin @(negedge clk);cycles=cycles+1;if(cycles>1000)$fatal(1,"audio deadline");end
  if(cycles!=896)$fatal(1,"28 voices must finish in896 clocks: %0d",cycles);
  if(deadline_fault||mixed_sample>16384||mixed_sample< -16384||$isunknown(mixed_sample))$fatal(1,"unsafe PCM");
  frames=frames+1;
 end endtask
 task select(input integer n);
 begin
  timbre_select=n;
  repeat(261)frame();
  if(dut.current_timbre!=n||dut.switch_state!=0||dut.fade_gain!=256)$fatal(1,"switch did not finish");
 end endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;wait(ready);
  for(p=0;p<5;p=p+1)begin
   key_gate=0;select((p+1)%5);select(p);key_gate=1;nonzero=0;peak[p]=0;signatures[p]=0;
   repeat(1024)begin frame();if(mixed_sample!=0)nonzero=nonzero+1;
    if(mixed_sample>peak[p])peak[p]=mixed_sample;signatures[p]=signatures[p]+mixed_sample;
   end
   if(nonzero<900||peak[p]==0||voice_active!=1)$fatal(1,"timbre p=%0d nonzero=%0d peak=%0d active=%h",p,nonzero,peak[p],voice_active);
   for(k=0;k<p;k=k+1)if(signatures[p]==signatures[k])$fatal(1,"identical timbres");
   // 持续28键切换后必须全静音，且持续压力不得自动再次发音。
   key_gate=28'hfffffff;repeat(8)frame();select((p+1)%5);
   repeat(12)begin frame();if(mixed_sample!=0||voice_active!=0)$fatal(1,"held keys retriggered after switch");end
   key_gate=0;repeat(2)frame();key_gate=28'hfffffff;repeat(256)frame();
   if(voice_active!=28'hfffffff)$fatal(1,"all28 polyphony");
   transpose=-5;repeat(16)frame();transpose=5;repeat(16)frame();transpose=0;
  end
  // 淡出中再次选择：以最后一次选择为准；无效编号安全回到钢琴。
  key_gate=1;timbre_select=1;repeat(40)frame();timbre_select=4;repeat(230)frame();
  if(dut.current_timbre!=4||voice_active!=0)$fatal(1,"rapid selection stale");
  timbre_select=7;repeat(261)frame();if(dut.current_timbre!=0)$fatal(1,"invalid profile");
  $display("PASS timbre_engine: %0d frames, five distinct profiles, all28, +/-5 transpose, held-key suppression, bounded switching",frames);$finish;
 end
 initial begin #500000000;$fatal(1,"timbre timeout");end
endmodule
