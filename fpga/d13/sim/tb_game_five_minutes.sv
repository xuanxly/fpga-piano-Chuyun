`timescale 1ns/1ps
module tb_game_five_minutes;
 reg clk=0;always #5 clk=~clk;reg rst_n=0,page_active=1,write=0;reg [27:0] keys=0;reg [5:0] address=0;reg [31:0] wdata=0;
 wire [31:0] rdata;wire [159:0] status;wire guide_active;wire [27:0] guide_keys,good_keys,bad_keys;
 game_engine28 #(.CLK_HZ(1000),.COUNTDOWN_MS(0)) d(.*);
 task wr(input [5:0] a,input [31:0] v);begin @(negedge clk);address=a;wdata=v;write=1;@(negedge clk);write=0;end endtask
 initial begin
  repeat(3)@(negedge clk);rst_n=1;wr(0,4);
  wr(4,240000);wr(8,1);wr(12,60000);wr(16,1);
  wr(4,300001);wr(8,32'h80000000);wr(12,0);wr(16,1);wr(0,1);
  wait(d.now_ms==240100);@(negedge clk);keys=1;
  wait(d.complete||d.fault);
  if(d.fault||d.now_ms<300100||d.hits!=1||d.misses!=0)$fatal(1,"Five-minute EOF/late held-note boundary failed now%0d hit%0d miss%0d",d.now_ms,d.hits,d.misses);
  $display("PASS game five-minute chart boundary: late hit,sustained final note,EOF after300000ms,no premature timeout");$finish;
 end
 initial begin #4000000;$fatal(1,"Five-minute test timeout");end
endmodule
