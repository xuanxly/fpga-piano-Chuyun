`timescale 1ns/1ps
module tb_d12_ui;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,frame_valid=0,connected=1,nav_valid=0,game_running=0,usb_exported=0;
 reg [2:0] nav_page=0;reg [4:0] active=0;reg [39:0] ids=0;reg [49:0] xs=0,ys=0;
 wire [27:0] touch_keys;wire [6:0] volume_percent;wire [2:0] page,timbre_selected;
 wire transpose_set_valid,command_valid;wire signed [3:0] transpose_set;wire [31:0] command;
 media_ui28 d(.*);integer checks=0,commands=0;reg [31:0] last;
 always @(negedge clk)if(command_valid)begin commands++;last=command;end
 task send;begin @(negedge clk);frame_valid=1;@(negedge clk);frame_valid=0;repeat(5)@(negedge clk);end endtask
 task clear;begin active=0;send();end endtask
 task tap(input integer x,y);begin clear();active=1;ids[7:0]=11;xs[9:0]=x;ys[9:0]=y;send();clear();end endtask
 task nav(input integer p);begin clear();nav_valid=1;nav_page=p;@(negedge clk);nav_valid=0;end endtask
 integer want,prev;
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  for(integer i=0;i<6;i++)begin
    nav(0);tap(100+(i%3)*224,150+(i/3)*168);
    case(i)0:want=1;1:want=2;2:want=3;3:want=4;4:want=6;default:want=7;endcase
    if(page!=want)$fatal(1,"Home tile%0d gotpage%0d",i,page);checks++;
  end
  for(integer k=0;k<28;k++)begin
    clear();active=1;ids[7:0]=k;xs[9:0]=20+(k%7)*96;ys[9:0]=270+(k/7)*30;send();
    if(touch_keys!=(28'd1<<k))$fatal(1,"GAME key%0d got%h",k,touch_keys);checks++;
  end
  tap(100,90);if(last!=32'h0f000000)$fatal(1,"Song selection failed");checks++;
  game_running=1;prev=commands;tap(100,90);if(commands!=prev)$fatal(1,"Running song can replace file");checks++;
  tap(100,410);if(last!=32'h10000000)$fatal(1,"Game mode button");
  tap(300,410);if(last!=32'h11000000)$fatal(1,"Game pause button");
  tap(550,410);if(last!=32'h12000000)$fatal(1,"Game stop button");checks+=3;
  clear();active=7;ids=40'h0000030201;xs={20'd0,10'd780,10'd725,10'd20};ys={20'd0,10'd400,10'd232,10'd270};send();
  if(touch_keys!=1||volume_percent!=50||!d.tone_owned||transpose_set!=-5)$fatal(1,"GAME simultaneous key/dualbars failed");checks++;
  nav(4);tap(550,80);if(last!=32'h13000000)$fatal(1,"USB DISK action");checks++;
  usb_exported=1;prev=commands;tap(100,110);tap(740,450);if(page!=4||commands!=prev)$fatal(1,"Export does not lock file/exit actions");checks++;
  tap(550,80);if(last!=32'h13000000)$fatal(1,"Export EJECT action lost");checks++;
  usb_exported=0;tap(740,450);if(page!=0)$fatal(1,"Post-export Home blocked");checks++;
  $display("PASS D12 UI %0d checks: six Home tiles,all28 GAME keys,one-shot commands,bar multitouch,USB owner lock/eject",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"D12 UI timeout");end
endmodule
