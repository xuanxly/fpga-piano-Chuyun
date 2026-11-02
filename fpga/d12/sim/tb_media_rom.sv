`timescale 1ns/1ps
module tb_media_rom;
 reg clk=0,enable=0;always #10 clk=~clk;reg [14:0] address=0;wire [31:0] q;reg [31:0] reference[0:19455];integer checks=0;
 media_rom dut(.clk(clk),.enable(enable),.address(address),.q(q));
 task read(input integer at);begin
  @(negedge clk);enable=1;address=at;@(posedge clk);#1;
  if(q!==reference[at])$fatal(1,"banked ROM differs at word%0d got=%h expected=%h",at,q,reference[at]);checks++;
 end endtask
 initial begin $readmemh("rom/media_firmware.hex",reference);
  for(integer i=0;i<19456;i++)read(i);
  for(integer i=0;i<2048;i++)read((i*7193)%19456);
  @(negedge clk);enable=0;address=0;repeat(3)@(posedge clk);#1;
  if(q!==reference[(2047*7193)%19456])$fatal(1,"disabled ROM output changed");
  $display("PASS media_rom: %0d accesses, every firmware word + bank boundaries + randomized addressing + enable/latency; identical 76KB image",checks);$finish;
 end
endmodule
