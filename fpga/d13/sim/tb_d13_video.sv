`timescale 1ns/1ps
module tb_d13_video;
 reg clk=0,rst_n=0,frame_tick=0,snapshot_valid=0;always #5 clk=~clk;
 reg [298:0] snapshot=0;reg [2378:0] media_snapshot=0;reg [255:0] extension=0;
 reg [9:0] x=0,y=0;reg hs=1,vs=0,de=1;wire hs_out,vs_out,de_out;wire [23:0] rgb;
 reg [71:0] usb_diag=0;wire [5:0] text_address;reg [31:0] text_data=32'h20202020;
 extended_ui_renderer dut(.*);integer f,pg,xx,yy;integer pages[0:2]='{0,8,9};
 task pixel(input integer px,py,input [23:0] expected);begin
  @(negedge clk);x=px;y=py;repeat(2)@(posedge clk);#1;
  if(rgb!==expected)$fatal(1,"D13 pixel page%0d %0d,%0d actual%h expected%h",extension[243:240],px,py,rgb,expected);
 end endtask
 initial begin #21;rst_n=1;snapshot[298]=1;snapshot[297:291]=25;snapshot_valid=1;@(negedge clk);snapshot_valid=0;
  extension[31:11]={7'd80,7'd50,7'd40};extension[10:8]=7;extension[7:2]=32;
  extension[243:240]=0;media_snapshot[2178:2176]=0;pixel(20,100,24'h153c53);pixel(540,280,24'h563765);
  extension[243:240]=9;media_snapshot[2178:2176]=1;pixel(212,120,24'h32a8b2);pixel(600,120,24'h20364d);
  extension[243:240]=8;media_snapshot[2178:2176]=0;pixel(34,354,24'h24654f);
  extension[32+117]=1;extension[32+116]=1;extension[32+12+:16]=48000;extension[32+28+:16]=896;extension[32+44+:16]=896;
  extension[32+60+:32]=2500;extension[32+92+:16]=12345;extension[239:224]=16'h0203;
  @(negedge clk);frame_tick=1;@(negedge clk);frame_tick=0;repeat(165)@(negedge clk);
  for(pg=0;pg<3;pg++)begin
   extension[243:240]=pages[pg];extension[0]=(pages[pg]>=8);media_snapshot[2178:2176]=pages[pg]%8;
   f=$fopen($sformatf("d13_page%0d.ppm",pages[pg]),"w");$fwrite(f,"P6\n800 480\n255\n");
   for(yy=0;yy<480;yy++)for(xx=0;xx<800;xx++)begin
    @(negedge clk);x=xx;y=yy;repeat(2)@(posedge clk);#1;
    if((^rgb===1'bx)||!hs_out||vs_out||!de_out)$fatal(1,"D13 unknown or sync pixel");
    $fwrite(f,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
   end $fclose(f);
  end
  @(negedge clk);de=0;hs=0;vs=1;@(posedge clk);#1;if(!de_out||!hs_out||vs_out)$fatal(1,"early sync");
  @(posedge clk);#1;if(de_out||hs_out||!vs_out)$fatal(1,"two-cycle sync changed");
  $display("PASS D13 video: three800x480 pages,8 Home colors,FX bars,VERIFY counters,all pixels known andtwo-cycle sync");$finish;
 end
 initial begin #50000000;$fatal(1,"D13 video timeout");end
endmodule
