`timescale 1ns/1ps
module tb_timbre_ui;
    wire usb_exported=0,game_running=0;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,frame_valid=0,connected=1,nav_valid=0;reg [2:0] nav_page=0;
 reg [4:0] active=0;reg [39:0] ids=0;reg [49:0] xs=0,ys=0;
 wire [27:0] touch_keys;wire [6:0] volume_percent;wire [2:0] page,timbre_selected;
 wire transpose_set_valid,command_valid;wire signed [3:0] transpose_set;wire [31:0] command;
 media_ui28 dut(.*);integer n,changes=0;reg [2:0] previous=0;
 always @(negedge clk)if(timbre_selected!=previous)begin changes=changes+1;previous=timbre_selected;end
 task send;begin @(negedge clk);frame_valid=1;@(negedge clk);frame_valid=0;repeat(4)@(negedge clk);end endtask
 task clear;begin active=0;send();end endtask
 task tap(input integer px,py);begin clear();active=1;ids[7:0]=11;xs[9:0]=px;ys[9:0]=py;send();clear();end endtask
 task nav(input integer p);begin @(negedge clk);nav_valid=1;nav_page=p;@(negedge clk);nav_valid=0;clear();end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
  if(timbre_selected!=0)$fatal(1,"default must be piano");
  nav(0);tap(330,320);if(page!=6)$fatal(1,"fifth Home app");
  for(n=0;n<5;n=n+1)begin
   tap(200,120+n*60);if(timbre_selected!=n||touch_keys!=0)$fatal(1,"select profile %0d",n);
  end
  // 同一触点在五项之间滑动，不重复选择；松开重新点击才选择。
  clear();active=1;ids[7:0]=77;xs[9:0]=200;ys[9:0]=120;send();
  for(n=1;n<5;n=n+1)begin ys[9:0]=120+n*60;send();if(timbre_selected!=0)$fatal(1,"held action repeated");end
  clear();tap(200,360);if(timbre_selected!=4)$fatal(1,"released action failed");
  // 同时操作音量柱和音调柱，不能选成琴键或阻塞音色。
  clear();active=7;ids=40'h0000030201;xs={20'd0,10'd780,10'd725,10'd200};ys={20'd0,10'd400,10'd232,10'd240};send();
  if(timbre_selected!=2||volume_percent!=50||!dut.tone_owned||touch_keys!=0)$fatal(1,"timbre+dual bars multi-touch");
  clear();tap(740,450);if(page!=0||timbre_selected!=2)$fatal(1,"Home selection persistence");
  tap(450,120);if(page!=2)$fatal(1,"keyboard app");
  tap(20,100);if(timbre_selected!=2)$fatal(1,"keyboard changed timbre");
  nav(3);tap(100,380);if(command[31:24]!=2)$fatal(1,"record action regression");
  nav(5);tap(280,240);if(page!=4)$fatal(1,"player exit regression");
  nav(6);active=1;xs[9:0]=200;ys[9:0]=180;send();connected=0;repeat(4)@(negedge clk);
  if(touch_keys!=0||timbre_selected!=1)$fatal(1,"disconnect lost selection");
  $display("PASS timbre_ui: five apps, all five profiles, held action, multi-touch, bars, Home, recorder/player coexistence");$finish;
 end
 initial begin #1000000;$fatal(1,"UI timeout");end
endmodule
