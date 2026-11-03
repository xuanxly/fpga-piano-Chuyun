`timescale 1ns/1ps
module tb_media_ui;
    wire usb_exported=0,game_running=0;
 reg clk=0,rst_n=0,frame_valid=0,connected=1,nav_valid=0;always #10 clk=~clk;
 reg [4:0] active=0;reg [39:0] ids=0;reg [49:0] xs=0,ys=0;reg [3:0] nav_page=0;
 wire [27:0] touch_keys;wire [6:0] volume_percent;wire [2:0] page;wire transpose_set_valid,command_valid;wire signed [3:0] transpose_set;wire [31:0] command;
 wire [2:0] timbre_selected;
 media_ui28 dut(.*);wire validation_run;wire [5:0] validation_count;wire [2:0] fx_enabled;wire [20:0] fx_levels;integer events=0,checks=0;reg [31:0] last;
 always @(posedge clk)begin #1;if(command_valid)begin events++;last=command;end end
 task send;begin @(negedge clk);frame_valid=1;@(negedge clk);frame_valid=0;repeat(2)@(negedge clk);#1;checks++;end endtask
 task clear;begin active=0;send();end endtask
 task finger(input integer s,id,x,y);begin active[s]=1;ids[s*8+:8]=id;xs[s*10+:10]=x;ys[s*10+:10]=y;end endtask
 task tap(input integer x,y);begin clear();finger(0,1,x,y);send();clear();end endtask
 task navigate(input integer p);begin clear();@(negedge clk);nav_valid=1;nav_page=p;@(negedge clk);nav_valid=0;end endtask
 task expect_command(input integer cmd,arg);begin if(last!==((cmd<<24)|arg))$fatal(1,"command got %h expected %h",last,(cmd<<24)|arg);end endtask
 integer prev;
 initial begin #101;rst_n=1;
  tap(740,450);tap(550,150);if(page!=3)$fatal(1,"recorder home tile");expect_command(1,3);
  for(integer k=0;k<28;k++)begin clear();finger(0,k,20+k%7*96,100+k/7*60);send();if(touch_keys!==(28'd1<<k))$fatal(1,"recorder key %0d",k);end
  tap(100,390);expect_command(2,0);tap(450,390);expect_command(3,0);
  clear();finger(0,3,100,390);send();prev=events;repeat(3)send();if(events!=prev)$fatal(1,"held RECORD toggled repeatedly");
  tap(740,450);tap(100,300);if(page!=4)$fatal(1,"file tile");
  tap(100,110);expect_command(4,0);tap(100,330);expect_command(4,5);
  tap(40,400);expect_command(5,0);tap(200,400);expect_command(6,0);tap(400,400);expect_command(7,0);tap(550,400);expect_command(8,0);
  navigate(5);clear();finger(0,1,776,64);send();if(transpose_set_valid)$fatal(1,"player pitch changed");
  tap(740,64);if(volume_percent!=100)$fatal(1,"player volume unavailable");
  clear();prev=events;finger(0,10,48,300);send();xs[9:0]=352;send();xs[9:0]=650;send();if(events!=prev)$fatal(1,"seek emitted before release");clear();expect_command(11,974);
  tap(100,380);expect_command(12,0);tap(300,380);expect_command(9,0);tap(500,380);expect_command(13,0);tap(100,240);expect_command(10,0);
  tap(280,240);if(page!=4)$fatal(1,"back FILES navigation");expect_command(1,4);
  navigate(3);clear();finger(0,10,20,100);finger(1,11,740,232);send();if(touch_keys!=1||volume_percent!=50)$fatal(1,"record keyboard and volume chord");
  nav_page=0;nav_valid=1;@(negedge clk);nav_valid=0;send();if(page||touch_keys)$fatal(1,"CPU nav key leakage");
  connected=0;#50;if(touch_keys)$fatal(1,"disconnect stuck key");
  $display("PASS media_ui: %0d touch frames; four apps, all28 recorder keys, one-shot actions, file rows/navigation, seek-on-release, player pitch lock, volume/multitouch",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"UI timeout");end
endmodule
