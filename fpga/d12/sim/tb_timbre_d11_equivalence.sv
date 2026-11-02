`timescale 1ns/1ps
// 与冻结D10并行逐样本比较未要求调整的三种音色；同时检查声部时限和清空。
module tb_timbre_d11_equivalence;
    wire vibrato_enable=0;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,sample_tick=0;reg [27:0] key_gate=0;reg [335:0] key_pressure=0;
 reg signed [3:0] transpose=0;reg [2:0] timbre_select=0;
 wire signed [15:0] mixed_sample,old_sample;wire frame_done,old_done;
 wire [27:0] voice_active,old_active;wire busy,ready,deadline_fault,old_busy,old_ready,old_fault;
 piano28_timbre_engine dut(.*);
 piano28_timbre_engine_d10 golden(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.key_gate(key_gate),.key_pressure(key_pressure),
 .transpose(transpose),.timbre_select(timbre_select),.mixed_sample(old_sample),.frame_done(old_done),.voice_active(old_active),
 .busy(old_busy),.ready(old_ready),.deadline_fault(old_fault));
 integer n,p,i,count=0;reg [31:0] rng=32'h13579bdf;
 task frame(input bit compare_pcm);
 begin
  @(negedge clk);sample_tick=1;@(negedge clk);sample_tick=0;n=0;
  while(!frame_done)begin @(negedge clk);n++;if(n>1000)$fatal(1,"deadline");end
  if(n!=896||!old_done||deadline_fault||old_fault)$fatal(1,"scheduling changed");
  if(compare_pcm&&(mixed_sample!==old_sample||voice_active!==old_active))
   $fatal(1,"unmodified tone differs: profile%0d frame%0d PCM%0d/%0d",timbre_select,count,mixed_sample,old_sample);
  count++;
 end endtask
 initial begin
  #101;rst_n=1;wait(ready&&old_ready);
  for(p=0;p<5;p++)if(p==0||p==2||p==4)begin
   key_gate=0;timbre_select=p;repeat(270)frame(0);
   for(i=0;i<2500;i++)begin
    rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
    if(i%67==0)key_gate=rng[27:0];
    if(i%131==0)begin transpose=(i%11)-5;key_pressure={28{rng[11:0]}};end
    frame(1);
   end
  end
  $display("PASS d11_equivalence: 7500 bit-exact PCM/active comparisons for piano, organ, strings; 896-clock frames");$finish;
 end
 initial begin #400000000;$fatal(1,"equivalence timeout");end
endmodule
