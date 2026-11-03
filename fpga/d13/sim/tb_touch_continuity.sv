`timescale 1ns/1ps
module touch_continuity_case #(parameter integer CASE_ID=0);
 reg clk=0,rst_n=0,connected=1,report_valid=0;always #5 clk=~clk;
 reg [6:0] report_length=11;reg [87:0] report_data=0;
 wire frame_valid,protocol_error;wire [4:0] active;wire [39:0] ids;wire [49:0] xs,ys;
 ws170120_reports #(.INCOMPLETE_CYCLES(80)) dut(.*);
 task packet(input integer count,cid,tip,x,y,stamp);begin
  @(negedge clk);report_data={count[7:0],stamp[15:0],y[15:0],x[15:0],8'd5,cid[7:0],7'd0,tip[0],8'd1};report_valid=1;
  @(posedge clk);#1;@(negedge clk);report_valid=0;
 end endtask
 initial begin #21;rst_n=1;packet(1,7,1,100,100,100);
  if(active!=1)$fatal(1,"fixture press");
  if(CASE_ID==0)begin
   packet(1,7,1,200,100,100);if(xs[9:0]!=200)$fatal(1,"new DATA with same scan time discarded: drag freezes");
   packet(1,7,0,200,100,100);if(active!=0)$fatal(1,"same-time real release discarded");
   packet(1,7,1,100,100,101);packet(0,7,0,100,100,102);if(active!=0)$fatal(1,"orphan release should release known contact");
  end else begin
   packet(2,7,1,110,100,101);repeat(100)@(negedge clk);
   if(active!=1)$fatal(1,"incomplete next frame erased last valid held contact");
   if(!protocol_error)$fatal(1,"missing continuation diagnostic absent");
   packet(2,7,1,120,100,102);packet(0,8,1,200,100,102);if(active!=3)$fatal(1,"recovery not atomic");
   packet(2,7,0,120,100,103);packet(0,8,0,200,100,103);if(active!=0)$fatal(1,"complete release");
  end
  connected=0;repeat(3)@(negedge clk);if(active!=0)$fatal(1,"disconnect stuck key");
  $display("PASS touch continuity case%0d: changed report vs timestamp, explicit release, incomplete retention and disconnect",CASE_ID);$finish;
 end
endmodule
module tb_touch_same_stamp;touch_continuity_case #(.CASE_ID(0)) c();endmodule
module tb_touch_incomplete_hold;touch_continuity_case #(.CASE_ID(1)) c();endmodule
