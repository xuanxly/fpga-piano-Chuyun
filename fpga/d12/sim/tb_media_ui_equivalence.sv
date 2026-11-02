`timescale 1ns/1ps
// 原始单拍规则为独立参考；新UI只增加一拍，不改变五指归属、优先级和命令。
module tb_media_ui_equivalence;
    wire usb_exported=0,game_running=0;
 reg clk=0,rst_n=0,frame_valid=0,connected=1,nav_valid=0;always #10 clk=~clk;
 reg [4:0] active=0;reg [39:0] ids=0;reg [49:0] xs=0,ys=0;reg [2:0] nav_page=0;
 wire [27:0] touch_keys,rkeys;wire [6:0] volume_percent,rvolume;wire [2:0] page,rpage;
 wire transpose_set_valid,rtv,command_valid,rcv;wire signed [3:0] transpose_set,rtone;wire [31:0] command,rcmd;
 wire [2:0] timbre_selected;
 media_ui28 dut(.*);
 media_ui28_reference reference(.clk(clk),.rst_n(rst_n),.frame_valid(frame_valid),.connected(connected),.active(active),.ids(ids),.xs(xs),.ys(ys),.nav_valid(nav_valid),.nav_page(nav_page),
 .touch_keys(rkeys),.volume_percent(rvolume),.page(rpage),.transpose_set_valid(rtv),.transpose_set(rtone),.command_valid(rcv),.command(rcmd));
 reg [27:0] saved_keys;reg [6:0] saved_volume;reg [2:0] saved_page;reg saved_tv,saved_cv;reg signed [3:0] saved_tone;reg [31:0] saved_cmd;
 integer checks=0,seed=32'h2810d9f4;integer random_value;
 function integer rnd(input integer size);begin random_value=$random(seed)&32'h7fffffff;rnd=random_value%size;end endfunction
 task report;begin
  @(negedge clk);frame_valid=1;@(posedge clk);#1;
  saved_keys=rkeys;saved_volume=rvolume;saved_page=rpage;saved_tv=rtv;saved_tone=rtone;saved_cv=rcv;saved_cmd=rcmd;
  @(negedge clk);frame_valid=0;@(posedge clk);#1;
  if(touch_keys!==saved_keys||volume_percent!==saved_volume||page!==saved_page||transpose_set_valid!==saved_tv||command_valid!==saved_cv||
     (saved_tv&&transpose_set!==saved_tone)||(saved_cv&&command!==saved_cmd))
   $fatal(1,"UI differs report%0d page%0d/%0d keys%h/%h vol%0d/%0d command%h/%h active%h",checks,page,saved_page,touch_keys,saved_keys,volume_percent,saved_volume,command,saved_cmd,active);
  checks++;@(negedge clk);
 end endtask
 initial begin
  #101;rst_n=1;
  for(integer n=0;n<100000;n++)begin
   if(n%31==0)begin
    @(negedge clk);nav_valid=1;nav_page=rnd(6);@(negedge clk);nav_valid=0;
    if(page!==rpage||touch_keys!==rkeys)$fatal(1,"CPU navigation mismatch");
   end
   for(integer i=0;i<5;i++)begin
    active[i]=rnd(4)!=0;ids[i*8+:8]=rnd(10);
    case(rnd(5))
     0:begin xs[i*10+:10]=16+rnd(7)*96;ys[i*10+:10]=100+rnd(4)*60;end
     1:begin xs[i*10+:10]=740;ys[i*10+:10]=rnd(480);end
     2:begin xs[i*10+:10]=776;ys[i*10+:10]=rnd(480);end
     default:begin xs[i*10+:10]=rnd(800);ys[i*10+:10]=rnd(480);end
    endcase
   end
   report();
  end
  connected=0;#50;if(touch_keys||rkeys)$fatal(1,"disconnect failed");
  connected=1;active=0;report();
  // CPU导航正好打断一级译码：必须取消旧页面结果，不能在下一拍弹回。
  @(negedge clk);frame_valid=1;active=1;xs[9:0]=740;ys[9:0]=450;
  @(negedge clk);frame_valid=0;nav_valid=1;nav_page=5;
  @(negedge clk);nav_valid=0;repeat(3)@(negedge clk);
  if(page!=5||touch_keys||command_valid)$fatal(1,"inflight frame overrode CPU navigation");
  $display("PASS media_ui_equivalence: %0d randomized five-contact reports against original rules, all six pages, ID reorder/ownership, action priority, volume/pitch/seek, plus in-flight CPU nav cancellation",checks);$finish;
 end
 initial begin #10000000;$fatal(1,"UI equivalence timeout");end
endmodule
