`timescale 1ns/1ps
module tb_media_video;
 reg clk=0,rst_n=0,frame_tick=0,snapshot_valid=0;always #5 clk=~clk;
 reg [298:0] snapshot=0;reg [2378:0] media_snapshot=0;reg [9:0] x=0,y=0;reg hs=1,vs=0,de=1;
 wire [5:0] text_address;reg [31:0] text_data;reg [31:0] textmem[0:63];
 always @(posedge clk)text_data<=textmem[text_address];
 wire hs_out,vs_out,de_out;wire [23:0] rgb;reg [71:0] usb_diag=0;
 media_ui_renderer dut(.*);integer f,xx,yy,pg;reg [255:0] ascii;
 task row(input integer n,input string s);begin
  if(s.len()>32)$fatal(1,"preview fixture exceeds one text row: %0d",s.len());
  for(integer i=0;i<32;i++)textmem[n*8+i/4][(i%4)*8+:8]=i<s.len()?s[i]:8'd32;
 end endtask
 task pixel(input integer px,py,input [23:0] expected);begin @(negedge clk);x=px;y=py;repeat(2)@(posedge clk);#1;if(rgb!==expected)$fatal(1,"media pixel %0d,%0d got=%h expected=%h",px,py,rgb,expected);end endtask
 initial begin for(integer i=0;i<64;i++)textmem[i]=32'h20202020;#21;rst_n=1;snapshot[298]=1;snapshot[297:291]=50;snapshot[256]=1;snapshot[264]=1;
  media_snapshot[2048]=1;media_snapshot[2049]=1;media_snapshot[2052:2050]=1;media_snapshot[2055:2053]=1;media_snapshot[2063:2056]=50;
  media_snapshot[2095:2080]=87;media_snapshot[2111:2096]=93;media_snapshot[2127:2112]=186;media_snapshot[2135:2128]=6;
  row(0,"REC0001.WAV                     ");row(1,"demo.wav                        ");row(2,"FOLDER                         /");row(3,"REC0002.WAV                     ");row(4,"LONG ENGLISH FILE NAME.WAV      ");row(5,"TEST.WAV                        ");row(6,"/                               ");row(7,"demo.wav                        ");
  #1;if(dut.upper_char("d")!="D"||dut.upper_char("m")!="M")$fatal(1,"lowercase file names are invisible");
  media_snapshot[2178:2176]=3;pixel(20,100,24'h32d3b8);pixel(116,100,24'hd9e2ef);
  media_snapshot[2178:2176]=5;pixel(100,300,24'h4794ed);pixel(600,300,24'h263d54);pixel(770,200,24'h263d54);
  media_snapshot[2178:2176]=6;media_snapshot[2213:2211]=3;
  pixel(50,300,24'h51e5a6);pixel(60,120,24'h193149);
  media_snapshot[2178:2176]=0;pixel(40,100,24'h153c53);pixel(260,100,24'h223655);pixel(480,100,24'h493040);pixel(40,280,24'h4b4325);pixel(260,280,24'h34445d);pixel(480,280,24'h285643);
  media_snapshot[2178:2176]=7;media_snapshot[2347]=1;media_snapshot[2220]=1;media_snapshot[2251+:24]=24'h012345;
  pixel(120,270,24'h4794ed);pixel(220,270,24'hd9e2ef);
  for(pg=0;pg<8;pg++)begin
   @(negedge clk);media_snapshot[2178:2176]=pg;snapshot[290:289]=pg;snapshot_valid=1;
   // 游戏与录放互斥；预览使用真实可达状态，不能沿用播放器的WAV标题和REC状态。
   if(pg==7)begin media_snapshot[2052:2050]=0;media_snapshot[2055:2053]=0;row(7,"CHORDS.CSV");end
   @(negedge clk);snapshot_valid=0;
   f=$fopen($sformatf("media_page%0d.ppm",pg),"w");$fwrite(f,"P3\n800 480\n255\n");
   for(yy=0;yy<480;yy++)for(xx=0;xx<800;xx++)begin
    @(negedge clk);x=xx;y=yy;repeat(2)@(posedge clk);#1;
    if(!de_out||!hs_out||vs_out||(^rgb===1'bx))$fatal(1,"video pipeline/X pixel page%0d x%0d y%0d",pg,xx,yy);
    $fwrite(f,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);
   end $fclose(f);
  end
  $display("PASS media_video: eight complete 800x480 RTL-rendered pages, timbre selection, six Home apps, file names, record keys, progress, player pitch lock, two-cycle sync");$finish;
 end
 initial begin #80000000;$fatal(1,"video timeout");end
endmodule
