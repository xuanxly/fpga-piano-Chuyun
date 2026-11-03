`timescale 1ns/1ps
module tb_timbre_pressure;
    wire vibrato_enable=0;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,sample_tick=0;reg [27:0] key_gate=0;reg [335:0] key_pressure={28{12'd4095}};
 reg signed [3:0] transpose=0;reg [2:0] timbre_select=2;
 wire signed [15:0] mixed_sample;wire frame_done;wire [27:0] voice_active;wire busy,ready,deadline_fault;
 piano28_timbre_engine dut(.*);integer cycles;longint signed high_energy=0,low_energy=0;
 task frame;begin @(negedge clk);sample_tick=1;@(negedge clk);sample_tick=0;cycles=0;
  while(!frame_done)begin @(negedge clk);cycles++;if(cycles>1000)$fatal(1,"late frame");end
  if(deadline_fault)$fatal(1,"deadline");end endtask
 initial begin
  #101;rst_n=1;wait(ready);repeat(270)frame();key_gate=28'd1<<7;repeat(1024)frame();
  repeat(2048)begin frame();high_energy+=longint'(mixed_sample)*mixed_sample;end
  key_pressure={28{12'd1024}};repeat(1024)frame();
  repeat(2048)begin frame();low_energy+=longint'(mixed_sample)*mixed_sample;end
  if(high_energy<=0||low_energy*16<high_energy*9/10||low_energy*16>high_energy*11/10)$fatal(1,"quarter pressure energy %0d/%0d",low_energy,high_energy);
  key_gate=0;repeat(300)frame();if(voice_active!=0||mixed_sample!=0)$fatal(1,"organ release tail stuck");
  $display("PASS timbre_pressure: quarter force gives quarter RMS within5percent; organ tail fully releases");$finish;
 end
 initial begin #200000000;$fatal(1,"pressure timeout");end
endmodule
