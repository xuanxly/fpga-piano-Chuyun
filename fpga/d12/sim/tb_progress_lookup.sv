`timescale 1ns/1ps
// 独立保留D9原乘除法渲染器，核对256种输入与整个800像素进度条扫描。
module tb_progress_lookup;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,frame_tick=0,snapshot_valid=0;reg [298:0] snapshot=0;reg [2213:0] media_snapshot=0;
 reg [9:0] x=0,y=300;reg hs=1,vs=0,de=1;reg [71:0] usb_diag=0;
 wire a_h,a_v,a_d,b_h,b_v,b_d;wire [23:0] a_rgb,b_rgb;wire [5:0] a_address,b_address;
 media_ui_renderer current(.clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),.snapshot_valid(snapshot_valid),.snapshot(snapshot),.media_snapshot(media_snapshot),
  .x(x),.y(y),.hs(hs),.vs(vs),.de(de),.usb_diag(usb_diag),.hs_out(a_h),.vs_out(a_v),.de_out(a_d),.rgb(a_rgb),.text_address(a_address),.text_data(32'h20202020));
 media_renderer_d9_reference original(.clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),.snapshot_valid(snapshot_valid),.snapshot(snapshot),.media_snapshot(media_snapshot[2210:0]),
  .x(x),.y(y),.hs(hs),.vs(vs),.de(de),.usb_diag(usb_diag),.hs_out(b_h),.vs_out(b_v),.de_out(b_d),.rgb(b_rgb),.text_address(b_address),.text_data(32'h20202020));
 integer p,xx,checks=0;
 initial begin
  #21;rst_n=1;media_snapshot[2178:2176]=5;
  for(p=0;p<256;p++)begin
   media_snapshot[2063:2056]=p;#1;
   if(current.progress_width!==original.progress_width)$fatal(1,"progress arithmetic mismatch %0d",p);
   for(xx=0;xx<800;xx++)begin @(negedge clk);x=xx;repeat(2)@(posedge clk);#1;
    if({a_h,a_v,a_d,a_rgb}!={b_h,b_v,b_d,b_rgb})$fatal(1,"progress pixel mismatch p=%0d x=%0d",p,xx);checks++;
   end
  end
  $display("PASS progress_lookup: all256 input values and %0d pixels exactly equal original D9 multiply/divide renderer",checks);$finish;
 end
 initial begin #10000000;$fatal(1,"progress timeout");end
endmodule
