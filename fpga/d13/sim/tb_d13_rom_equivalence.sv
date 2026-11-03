`timescale 1ns/1ps
// 改变ROM的物理推断方式后，全部有效地址、保持及随机访问必须逐字等价。
module tb_d13_rom_equivalence;
 reg clk=0,enable=0;always #10 clk=~clk;
 reg [14:0] address=0;wire [31:0] block_q,legacy_q;
 reg [31:0] expected[0:10239],held;integer i,checks=0;reg [31:0] rng=32'h1d13f611;
 media_rom #(.WORDS(10240),.LUT_BANKS(0)) block_rom(.clk(clk),.enable(enable),.address(address),.q(block_q));
 media_rom #(.WORDS(10240),.LUT_BANKS(4)) legacy_rom(.clk(clk),.enable(enable),.address(address),.q(legacy_q));
 task access(input integer a,input bit e);begin
  @(negedge clk);address=a;enable=e;
  if(e)held=expected[a];
  @(posedge clk);#1;
  if(block_q!==held||legacy_q!==held)$fatal(1,"ROM inference changed data/latency at %d: %h %h expected %h",a,block_q,legacy_q,held);
  checks++;
 end endtask
 initial begin
  $readmemh("rom/media_firmware.hex",expected);
  for(i=0;i<10240;i++)access(i,1);
  for(i=0;i<4096;i++)begin rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);access(rng%10240,i%4!=0);end
  $display("PASS D13 ROM inference equivalence: %0d all-address/random/stall checks, exact data and one-cycle latency",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"ROM equivalence timeout");end
endmodule
