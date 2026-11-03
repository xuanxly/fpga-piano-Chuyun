`timescale 1ns/1ps
module tb_d13_ui;
 reg clk=0,rst_n=0,frame_valid=0,connected=1,game_running=0,usb_exported=0,nav_valid=0;always #5 clk=~clk;
 reg [4:0] active=0;reg [39:0] ids=40'h0504030201;reg [49:0] xs=0,ys=0;reg [3:0] nav_page=0;
 wire [27:0] touch_keys;wire [6:0] volume_percent;wire [3:0] page;wire transpose_set_valid;wire signed [3:0] transpose_set;
 wire command_valid,validation_run;wire [31:0] command;wire [2:0] timbre_selected,fx_enabled;wire [20:0] fx_levels;wire [5:0] validation_count;
 media_ui28 #(.ENABLE_EXTRA_APPS(1)) dut(.*);integer k;integer wanted[0:7]='{1,2,3,4,6,7,8,9};
 task frame(input integer down,px,py);begin
  @(negedge clk);active=down;xs[9:0]=px;ys[9:0]=py;frame_valid=1;@(negedge clk);frame_valid=0;repeat(7)@(negedge clk);
 end endtask
 task tap(input integer px,py);begin frame(1,px,py);frame(0,px,py);end endtask
 task home;begin tap(720,450);if(page!=0)$fatal(1,"Home inaccessible from page%0d",page);end endtask
 initial begin #21;rst_n=1;repeat(3)@(negedge clk);
  for(k=0;k<8;k++)begin home();tap(96+(k%4)*172,166+(k/4)*168);if(page!=wanted[k])$fatal(1,"Home app%0d mapped%0d",k,page);end
  home();tap(440,334);if(validation_run||validation_count!=32)$fatal(1,"verify must start silent");
  frame(1,80,380);if(!validation_run)$fatal(1,"START not active");frame(1,80,380);if(!validation_run)$fatal(1,"held START toggles repeatedly");frame(0,80,380);
  tap(512,310);if(validation_count!=28||!validation_run)$fatal(1,"count change");home();if(validation_run)$fatal(1,"test sound sticks after leaving");
  tap(612,334);for(k=0;k<3;k++)tap(80,128+k*104);if(fx_enabled!=7)$fatal(1,"three independent effect toggles");
  tap(400,128);if(fx_levels[6:0]!=48)$fatal(1,"reverb slider");
  frame(1,400,232);frame(1,640,420);if(fx_levels[13:7]!=100)$fatal(1,"slider must retain owner and clamp after drag outside row");frame(0,640,420);
  tap(208,336);if(fx_levels[20:14]!=0)$fatal(1,"chorus minimum");home();if(fx_enabled!=7||fx_levels[6:0]!=48)$fatal(1,"effects not persistent");
  tap(268,166);frame(1,60,120);if(touch_keys!==28'd1)$fatal(1,"keyboard regression after new pages");frame(0,60,120);if(touch_keys!=0)$fatal(1,"release");
  $display("PASS D13 UI: all8 Home entries, silent test entry, edge START, counts, exit stop, three independent FX/drag/persistence and keyboard");$finish;
 end
 initial begin #100000;$fatal(1,"D13 UI timeout");end
endmodule
