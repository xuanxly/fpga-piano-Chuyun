`timescale 1ns/1ps
// 与优化前UI逐帧对照；允许提交多一拍，但多指归属、操作顺序和所有持久状态必须相同。
module tb_d12_ui_pipeline;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,frame_valid=0,connected=1,game_running=0,usb_exported=0,nav_valid=0;
 reg [4:0] active=0;reg [39:0] ids=0;reg [49:0] xs=0,ys=0;reg [3:0] nav_page=0;
 wire [27:0] keys_new,keys_old;wire [6:0] vol_new,vol_old;wire [3:0] page_new;wire [2:0] page_old,timbre_new,timbre_old;
 wire tv_new,tv_old,cv_new,cv_old;wire signed [3:0] tone_new,tone_old;wire [31:0] cmd_new,cmd_old;
 media_ui28 n(clk,rst_n,frame_valid,connected,active,ids,xs,ys,game_running,usb_exported,nav_valid,nav_page,keys_new,vol_new,page_new,tv_new,tone_new,cv_new,cmd_new,timbre_new);
 d12_ui_pipeline_reference o(clk,rst_n,frame_valid,connected,active,ids,xs,ys,game_running,usb_exported,nav_valid,nav_page[2:0],keys_old,vol_old,page_old,tv_old,tone_old,cv_old,cmd_old,timbre_old);
 integer cn=0,co=0,tn=0,to=0,frames=0;reg [31:0] ln=0,lo=0;
 always @(negedge clk)begin
   if(cv_new)begin cn++;ln=cmd_new;end if(cv_old)begin co++;lo=cmd_old;end
   if(tv_new)tn++;if(tv_old)to++;
 end
 reg [31:0] seed=32'h128ab345;
 function [31:0] rnd;begin seed=seed^(seed<<13);seed=seed^(seed>>17);seed=seed^(seed<<5);rnd=seed;end endfunction
 task check;
 begin
  #1;
  if(n.decode_pages!=={5{page_new}})$fatal(1,"Local page copies diverged page=%h actual=%h nav=%h",n.page,n.decode_pages,nav_page);
  if({keys_new,vol_new,page_new[2:0],timbre_new,tone_new}!={keys_old,vol_old,page_old,timbre_old,tone_old}||cn!=co||ln!=lo||tn!=to)
   $fatal(1,"UI equivalence frame%0d p%0d/%0d key%h/%h vol%0d/%0d commands%0d/%0d transpose%0d/%0d",frames,page_new,page_old,keys_new,keys_old,vol_new,vol_old,cn,co,tn,to);
  if({n.volume_owned,n.volume_id,n.tone_owned,n.tone_id,n.seek_owned,n.seek_id,n.seek_value,n.old_active}!=={o.volume_owned,o.volume_id,o.tone_owned,o.tone_id,o.seek_owned,o.seek_id,o.seek_value,o.old_active})$fatal(1,"UI ownership equivalence frame%0d",frames);
  for(integer j=0;j<5;j++)if(n.old_role[j*4+:4]!=={1'b0,o.old_role[j]}||n.old_id[j*8+:8]!==o.old_id[j])$fatal(1,"UI role frame%0d slot%0d",frames,j);
 end endtask
 task send;begin @(negedge clk);frame_valid=1;@(negedge clk);frame_valid=0;repeat(5)@(negedge clk);frames++;check();end endtask
 integer rr,xx,yy;
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  for(integer f=0;f<16000;f++)begin
   // 导航/拔出是即时事件，发生在已提交的USB帧之间。
   if((rnd()%19)==0)begin nav_page=rnd()%8;nav_valid=1;@(negedge clk);nav_valid=0;repeat(3)@(negedge clk);check();end
   if((rnd()%113)==0)begin connected=0;repeat(4)@(negedge clk);check();connected=1;end
   if((rnd()%7)==0)game_running=~game_running;
   if((rnd()%23)==0)usb_exported=~usb_exported;
   active=rnd()%32;
   for(integer j=0;j<5;j++)begin
    rr=rnd();if((rr&3)==0)ids[j*8+:8]=j*32+(rnd()%32);
    if((rr&7)==0)begin xx=704+(rnd()%96);yy=48+(rnd()%428);end
    else begin xx=rnd()%800;yy=rnd()%480;end
    xs[j*10+:10]=xx;ys[j*10+:10]=yy;
   end
   send();
  end
  active=0;send();
  $display("PASS D12 UI pipeline %0d randomized frames: all8 pages,5 contacts,owner IDs,drag/release,command order,transpose,timbre,CPU nav/unplug",frames);$finish;
 end
 initial begin #100000000;$fatal(1,"UI equivalence timeout");end
endmodule
