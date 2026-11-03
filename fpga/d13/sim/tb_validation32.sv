`timescale 1ns/1ps
module tb_validation32;
 reg clk=0,rst_n=0,sample_tick=0,enable=0;reg [5:0] count=32;always #5 clk=~clk;
 wire signed [15:0] pcm;wire valid,busy,ready,fault;wire [5:0] active_units;
 validation_tones32 dut(.*);integer n,f,cycles;reg [31:0] old_phase[0:31];
 task frame;begin
  for(integer k=0;k<32;k++)old_phase[k]=dut.phases[k];
  @(negedge clk);sample_tick=1;@(negedge clk);sample_tick=0;cycles=0;
  while(!valid)begin @(posedge clk);#1;cycles++;if(cycles>260)$fatal(1,"test engine deadline");end
  if(fault||(^pcm===1'bx)||active_units!==(enable?count:0))$fatal(1,"test tone status/X");
  for(integer k=0;k<32;k++)if(dut.phases[k]!==(enable?old_phase[k]:32'd0)+((k+1)<<25))$fatal(1,"phase context%0d",k);
 end endtask
 initial begin #21;rst_n=1;wait(ready);frame();if(pcm!=0)$fatal(1,"test starts audible without START");
  enable=1;f=$fopen("validation32_pcm.txt","w");for(n=0;n<4096;n++)begin frame();$fwrite(f,"%0d\n",pcm);end $fclose(f);
  count=1;repeat(100)frame();count=4;repeat(100)frame();count=8;repeat(100)frame();count=16;repeat(100)frame();count=28;repeat(100)frame();
  enable=0;frame();if(pcm!=0)$fatal(1,"STOP retained test sound");
  $display("PASS validation32: 32 independent phase accumulators, 4096 PCM samples, six counts, 256-cycle budget and silent STOP");$finish;
 end
 initial begin #15000000;$fatal(1,"validation timeout");end
endmodule
