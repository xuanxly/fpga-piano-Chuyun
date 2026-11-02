`timescale 1ns/1ps
// 厂商实际布局布线网表 + 原生 ROM/LUT 原语：验证固件初始化和一拍读口。
module tb_media_rom_native;
 reg clk=0,enable=0;always #10 clk=~clk;
 reg [14:0] address=0;wire [31:0] q;reg [31:0] reference[0:19455];integer checks=0;
 mem_probe dut(.clk(clk),.en(enable),.addr(address),.q(q));
 task read_word(input integer at);begin
  @(negedge clk);enable=1;address=at;@(posedge clk);#1;
  if(q!==reference[at])$fatal(1,"native ROM differs word=%0d got=%h expected=%h",at,q,reference[at]);checks++;
 end endtask
 initial begin
  $readmemh("rom/media_firmware.hex",reference);
  // 等待原生 GSR 的上电复位结束，不用 RTL 的未知初态判断物理行为。
  repeat(20)@(posedge clk);
  for(integer i=0;i<19456;i++)read_word(i);
  for(integer i=0;i<2048;i++)read_word((i*7193)%19456);
  @(negedge clk);enable=0;address=0;repeat(3)@(posedge clk);#1;
  if(q!==reference[(2047*7193)%19456])$fatal(1,"native disabled ROM changed");
  $display("PASS media_rom_native: %0d accesses; actual Gowin routed ROM/LUT netlist + vendor primitives; every 76KB firmware word, random address, enable and one-cycle latency",checks);$finish;
 end
endmodule
