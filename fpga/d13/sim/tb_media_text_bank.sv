`timescale 1ns/1ps
// 两个非同相时钟；繁忙中开始的软件包即使中途解除繁忙也必须整包拒绝。
module tb_media_text_bank;
 reg clk=0,pixel_clk=0,rst_n=0;always #10 clk=~clk;always #17 pixel_clk=~pixel_clk;
 reg display_bank=0;reg [5:0] text_address=0;wire [31:0] text_data;wire [2175:0] ui;
 reg req=0,we=0;reg [29:0] address=0;reg [31:0] data=0;integer checks=0;
 media_soc dut(.clk(clk),.rst_n(rst_n),.page(4'd4),.command_valid(1'b0),.command(32'd0),.record_valid(1'b0),.record_pcm(16'd0),.sample_tick(1'b0),.sd_miso(1'b1),.ui_snapshot(ui),.pixel_clk(pixel_clk),.display_bank(display_bank),.text_address(text_address),.text_data(text_data));
 task write(input integer off,input [31:0] v);begin
  @(negedge clk);req=1;we=1;address=(32'hf0000000+off)>>2;data=v;
  @(posedge clk);#1;if(!dut.dack)$fatal(1,"text write not acknowledged");
  @(negedge clk);req=0;@(posedge clk);#1;checks++;
 end endtask
 task text(input integer at,input [31:0] v);begin
  @(negedge pixel_clk);text_address=at;@(posedge pixel_clk);#1;
  if(text_data!==v)$fatal(1,"text bank data got=%h expected=%h addr=%0d bank=%b",text_data,v,at,display_bank);
 end endtask
 initial begin
  force dut.icyc=0;force dut.istb=0;force dut.dcyc=req;force dut.dstb=req;force dut.dwe=we;force dut.dadr=address;force dut.dout=data;force dut.dsel=4'hf;
  #101;rst_n=1;write(4096,32'h41414141);write(4100,32'h42424242);write(4352,32'haaaa1111);write(84,1);
  if(!ui[0]||!dut.ui_busy)$fatal(1,"commit/busy flag");text(0,32'h20202020);
  write(4096,32'h43434343); // 繁忙，整包应被拒绝。
  @(negedge pixel_clk);display_bank=ui[0];repeat(5)@(posedge clk);#1;if(dut.ui_busy)$fatal(1,"display acknowledgement did not cross domain");
  write(4100,32'h44444444);write(4352,32'hbbbb2222);write(84,1);
  if(ui[0]!=1||ui[2079:2048]!=32'haaaa1111)$fatal(1,"partial rejected packet committed");
  text(0,32'h41414141);text(1,32'h42424242);
  write(4096,32'h45454545);write(4100,32'h46464646);write(4352,32'hcccc3333);write(84,1);
  if(ui[0]!=0||ui[2079:2048]!=32'hcccc3333)$fatal(1,"next complete packet rejected");
  text(0,32'h41414141); // 仍显示旧银行，直到帧边界交换指针。
  @(negedge pixel_clk);display_bank=ui[0];text(0,32'h45454545);text(1,32'h46464646);
  $display("PASS media_text_bank: %0d writes, independent clocks, invisible-bank writes, frame-boundary pointer, busy whole-packet rejection, no torn text",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"text bank timeout");end
endmodule
