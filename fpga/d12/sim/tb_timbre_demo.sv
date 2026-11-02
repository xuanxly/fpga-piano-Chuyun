`timescale 1ns/1ps
// 从实际RTL导出48kHz PCM供独立频谱/包络检查和试听，不是Python另造声音。
module tb_timbre_demo;
    wire vibrato_enable=0;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,sample_tick=0;reg [27:0] key_gate=0;reg [335:0] key_pressure={28{12'd4095}};
 reg signed [3:0] transpose=0;reg [2:0] timbre_select=0;
 wire signed [15:0] mixed_sample;wire frame_done;wire [27:0] voice_active;wire busy,ready,deadline_fault;
 piano28_timbre_engine dut(.*);integer f,p,n,cycles,total=0;
 task frame(input integer save);
 begin
  @(negedge clk);sample_tick=1;@(negedge clk);sample_tick=0;cycles=0;
  while(!frame_done)begin @(negedge clk);cycles=cycles+1;if(cycles>1000)$fatal(1,"late PCM");end
  if(deadline_fault)$fatal(1,"deadline fault");
  if(save)begin $fwrite(f,"%0d\n",mixed_sample);total=total+1;end
 end endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;wait(ready);
  for(p=0;p<5;p=p+1)begin
   key_gate=0;timbre_select=p;repeat(261)frame(0);
   f=$fopen($sformatf("timbre_%0d.pcm.txt",p),"w");
   key_gate=28'd1<<7;repeat(24000)frame(1);
   key_gate=0;repeat(2400)frame(1);
   key_gate=28'd1<<9;repeat(9600)frame(1);
   key_gate=0;repeat(2400)frame(1);
   key_gate=28'd1<<11;repeat(9600)frame(1);
   key_gate=0;repeat(2400)frame(1);
   key_gate=(28'd1<<7)|(28'd1<<9)|(28'd1<<11);repeat(24000)frame(1);
   key_gate=0;repeat(28800)frame(1);$fclose(f);
  end
  $display("PASS timbre_demo: %0d actual RTL PCM samples, five instruments, single notes/chord/release",total);$finish;
 end
 initial begin #12000000000;$fatal(1,"render timeout");end
endmodule
