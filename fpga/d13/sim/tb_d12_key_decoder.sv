`timescale 1ns/1ps
module tb_d12_key_decoder;
 reg clk=0;always #5 clk=~clk;
 media_ui28 n(.clk(clk),.rst_n(1'b0),.frame_valid(1'b0),.connected(1'b0),.active(5'd0),.ids(40'd0),.xs(50'd0),.ys(50'd0),.game_running(1'b0),.usb_exported(1'b0),.nav_valid(1'b0),.nav_page(4'd0));
 d12_ui_pipeline_reference o(.clk(clk),.rst_n(1'b0),.frame_valid(1'b0),.connected(1'b0),.active(5'd0),.ids(40'd0),.xs(50'd0),.ys(50'd0),.game_running(1'b0),.usb_exported(1'b0),.nav_valid(1'b0),.nav_page(4'd0));
 integer checks=0;
 initial begin
 for(integer p=0;p<8;p++)for(integer y=0;y<1024;y++)for(integer x=0;x<1024;x++)begin
  if(n.key_at(p,x,y)!==o.key_at(p,x,y))$fatal(1,"Key decoder mismatch page%0d x%0d y%0d",p,x,y);checks++;
 end
 $display("PASS D12 key decoder:all%0d page/x/y combinations exact,includingallinvalidcoordinates",checks);$finish;
 end
endmodule
