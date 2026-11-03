`timescale 1ns/1ps
// 同一演奏输入同时驱动D10和D11；导出的是真实RTL PCM，不用软件另造声音。
module tb_timbre_d11_demo;
    wire vibrato_enable=0;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,sample_tick=0;reg [27:0] key_gate=0;reg [335:0] key_pressure={28{12'd4095}};
 reg signed [3:0] transpose=0;reg [2:0] timbre_select=0;
 wire signed [15:0] mixed_sample,old_sample;wire frame_done,old_done;
 wire [27:0] voice_active,old_active;wire busy,ready,deadline_fault,old_busy,old_ready,old_fault;
 piano28_timbre_engine dut(.*);
 piano28_timbre_engine_d10 golden(.clk(clk),.rst_n(rst_n),.sample_tick(sample_tick),.key_gate(key_gate),.key_pressure(key_pressure),
 .transpose(transpose),.timbre_select(timbre_select),.mixed_sample(old_sample),.frame_done(old_done),.voice_active(old_active),
 .busy(old_busy),.ready(old_ready),.deadline_fault(old_fault));
 integer f,p,n,total=0;
 task frame(input bit save);
 begin
  @(negedge clk);sample_tick=1;@(negedge clk);sample_tick=0;n=0;
  while(!frame_done)begin @(negedge clk);n++;if(n>1000)$fatal(1,"deadline");end
  if(n!=896||!old_done||deadline_fault||old_fault)$fatal(1,"scheduling");
  if(save)begin $fwrite(f,"%0d %0d\n",old_sample,mixed_sample);total++;end
 end endtask
 task tail;
 begin key_gate=0;repeat(48000)frame(1);if(voice_active!=0||mixed_sample!=0)$fatal(1,"tail not fully cleared");end
 endtask
 initial begin
  #101;rst_n=1;wait(ready&&old_ready);
  for(p=1;p<=3;p+=2)begin
   timbre_select=p;key_gate=0;repeat(270)frame(0);
   f=$fopen($sformatf("pair_%0d.pcm.txt",p),"w");
   key_gate=28'd1<<7;repeat(96000)frame(1);tail(); // C4持续两秒及完整释音
   key_gate=(28'd1<<0)|(28'd1<<2)|(28'd1<<4);repeat(24000)frame(1);tail(); // 三和弦
   transpose=5;key_gate=28'd1<<27;repeat(9600)frame(1);tail(); // 最高可用移调音
   transpose=0;key_pressure={28{12'd1024}};key_gate=28'd1<<7;repeat(24000)frame(1);tail(); // 轻按
   $fclose(f);key_pressure={28{12'd4095}};
  end
  $display("PASS d11_demo: %0d paired actual RTL samples, C4 sustain/chord/highest-note/soft-force/full release",total);$finish;
 end
 initial begin #20000000000;$fatal(1,"demo timeout");end
endmodule
