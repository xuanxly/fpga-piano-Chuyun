`timescale 1ns/1ps
module tb_media_ram_native;
 reg clk=0,enable=0,write=0;always #10 clk=~clk;
 reg [13:0] address=0;reg [33:0] data=0;reg [3:0] bytes=15;
 wire [31:0] ram_q;wire [33:0] audio_q;
 reg [31:0] expected[0:12287];reg [33:0] audio_expected[0:6143];integer checks=0;
 mem_ram_probe dut(.*);
 task store(input integer at,input [33:0] value,input [3:0] mask);begin
  @(negedge clk);enable=1;write=1;address=at;data=value;bytes=mask;
  @(posedge clk);#1;
  for(integer k=0;k<4;k++)if(mask[k])expected[at][k*8+:8]=value[k*8+:8];
  if(at<6144)audio_expected[at]=value;
 end endtask
 task load(input integer at);begin
  @(negedge clk);enable=1;write=0;address=at;@(posedge clk);#1;
  if(ram_q!==expected[at])$fatal(1,"work RAM native mismatch at=%0d got=%h expected=%h",at,ram_q,expected[at]);
  if(at<6144&&audio_q!==audio_expected[at])$fatal(1,"audio RAM native mismatch at=%0d got=%h expected=%h",at,audio_q,audio_expected[at]);
  checks++;
 end endtask
 initial begin
  repeat(20)@(posedge clk);
  for(integer i=0;i<12288;i++)store(i,{2'(i%3),32'h91b3a7e5^(i*7193)},15);
  for(integer i=0;i<12288;i++)load(i);
  for(integer i=0;i<12288;i++)begin store(i,{2'((i+1)%3),32'h6e7c58a1^(i*137)},1<<(i%4));load(i);end
  for(integer i=0;i<2048;i++)load((i*7193)%12288);
  @(negedge clk);enable=0;write=0;address=0;repeat(3)@(posedge clk);#1;
  if(ram_q!==expected[(2047*7193)%12288])$fatal(1,"native RAM disabled output changed");
  $display("PASS media_ram_native: %0d accesses; actual Gowin routed RAM + vendor primitives; 48KB work RAM byte masks, 24KiB single-port audio RAM including 2-bit valid metadata, bank boundaries and enable",checks);$finish;
 end
endmodule
