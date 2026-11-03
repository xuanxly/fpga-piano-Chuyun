`timescale 1ns/1ps
module tb_effects28;
 reg clk=0,rst_n=0,sample_valid=0;always #5 clk=~clk;
 reg signed [15:0] sample_in=0;reg [2:0] enabled=0;reg [6:0] reverb_level=100,echo_level=100,chorus_level=100;
 wire signed [15:0] sample_out;wire out_valid,ready,busy,fault,clipped;
 audio_effects28 dut(.*);integer file,n,latency;reg signed [15:0] result;reg done;
 task send(input integer value);begin
  @(negedge clk);sample_in=value;sample_valid=1;done=0;latency=0;
  @(negedge clk);sample_valid=0;
  // 共享RAM按26拍安排，32拍上界仍远小于48kHz帧的1041/1042拍。
  while(!done)begin @(posedge clk);#1;latency++;if(out_valid)begin result=sample_out;done=1;end if(latency>32)$fatal(1,"FX missed bounded deadline");end
  if(fault||(^result===1'bx))$fatal(1,"FX fault or X");
  $fwrite(file,"%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",enabled,sample_in,reverb_level,echo_level,chorus_level,result,clipped);
 end endtask
 initial begin
  file=$fopen("effects28_samples.csv","w");#21;rst_n=1;wait(ready);
  // 先验证正负满量程直通，再检验独立效果、三效果叠加和所有RAM回绕。
  for(n=0;n<300;n++)begin send((n*997)%65536-32768);if(result!==sample_in)$fatal(1,"FX bypass not exact");end
  enabled=2;for(n=0;n<15000;n++)send(n==0?16000:0);
  enabled=1;for(n=0;n<24000;n++)send(n==0?-12000:0);
  enabled=4;for(n=0;n<12000;n++)send(n<2000?((n*701)%8000-4000):0);
  enabled=7;for(n=0;n<40000;n++)send(n<20000?((n*661)%24000-12000):0);
  $fclose(file);$display("PASS effects28: 91300 samples, exact bypass, bounded latency, independent and stacked effects; compare independent model next");$finish;
 end
 initial begin #50000000;$fatal(1,"FX timeout");end
endmodule
