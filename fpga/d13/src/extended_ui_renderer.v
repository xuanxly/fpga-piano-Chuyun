`timescale 1ns/1ps
// 两个新页面的像素和数据格式化均为HDL；与原画面同为两拍流水，无帧缓存。
module extended_ui_renderer #(parameter integer ENABLE_USB_DIAG=1)(
 input wire clk,rst_n,frame_tick,snapshot_valid,input wire [298:0] snapshot,
 input wire [2378:0] media_snapshot,input wire [255:0] extension,input wire [9:0] x,y,input wire hs,vs,de,
 output wire hs_out,vs_out,de_out,output wire [23:0] rgb,input wire [71:0] usb_diag,
 output wire [5:0] text_address,input wire [31:0] text_data);
 wire [23:0] base_rgb;
 media_ui_renderer #(.ENABLE_USB_DIAG(ENABLE_USB_DIAG),.ENABLE_EXTRA_APPS(1)) u_base(
  .clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),.snapshot_valid(snapshot_valid),.snapshot(snapshot),.media_snapshot(media_snapshot),
  .x(x),.y(y),.hs(hs),.vs(vs),.de(de),.hs_out(hs_out),.vs_out(vs_out),.de_out(de_out),.rgb(base_rgb),
  .usb_diag(usb_diag),.text_address(text_address),.text_data(text_data));
 wire [3:0] page=extension[243:240]; // 完整页号来自同一快照，不能跨两个邮箱拼接。
 wire running=extension[1];wire [5:0] chosen=extension[7:2];wire [2:0] enabled=extension[10:8];wire [20:0] levels=extension[31:11];
 wire [191:0] st=extension[223:32];
 wire [199:0] decimals;
 validation_decimal_formatter u_numbers(.clk(clk),.rst_n(rst_n),.start(frame_tick),.status(st),.digits(decimals));
 function [7:0] decchar(input [39:0] digits,input integer pos);
  begin decchar="0"+digits[pos*4+:4];end
 endfunction
 function [7:0] small_digit(input [6:0] value,input integer pos);
  reg [6:0] n;begin n=(pos==2)?value/100:(pos==1)?value/10:value;small_digit="0"+n%10;end
 endfunction
 function [7:0] hexchar(input [3:0] v);begin hexchar=v<10?"0"+v:"A"+v-10;end endfunction
    function [34:0] glyph;
        input [7:0] c;
        begin
            case(c) // 五列七行点阵，行优先；未列出的字符为空格
                "0":glyph=35'b01110_10001_10011_10101_11001_10001_01110;
                "1":glyph=35'b00100_01100_00100_00100_00100_00100_01110;
                "2":glyph=35'b01110_10001_00001_00010_00100_01000_11111;
                "3":glyph=35'b11110_00001_00001_01110_00001_00001_11110;
                "4":glyph=35'b00010_00110_01010_10010_11111_00010_00010;
                "5":glyph=35'b11111_10000_10000_11110_00001_00001_11110;
                "6":glyph=35'b01110_10000_10000_11110_10001_10001_01110;
                "7":glyph=35'b11111_00001_00010_00100_01000_01000_01000;
                "8":glyph=35'b01110_10001_10001_01110_10001_10001_01110;
                "9":glyph=35'b01110_10001_10001_01111_00001_00001_01110;
                "A":glyph=35'b01110_10001_10001_11111_10001_10001_10001;
                "B":glyph=35'b11110_10001_10001_11110_10001_10001_11110;
                "C":glyph=35'b01111_10000_10000_10000_10000_10000_01111;
                "D":glyph=35'b11110_10001_10001_10001_10001_10001_11110;
                "E":glyph=35'b11111_10000_10000_11110_10000_10000_11111;
                "F":glyph=35'b11111_10000_10000_11110_10000_10000_10000;
                "G":glyph=35'b01111_10000_10000_10111_10001_10001_01111;
                "H":glyph=35'b10001_10001_10001_11111_10001_10001_10001;
                "I":glyph=35'b01110_00100_00100_00100_00100_00100_01110;
                "J":glyph=35'b00111_00010_00010_00010_10010_10010_01100;
                "K":glyph=35'b10001_10010_10100_11000_10100_10010_10001;
                "L":glyph=35'b10000_10000_10000_10000_10000_10000_11111;
                "M":glyph=35'b10001_11011_10101_10101_10001_10001_10001;
                "N":glyph=35'b10001_11001_10101_10011_10001_10001_10001;
                "O":glyph=35'b01110_10001_10001_10001_10001_10001_01110;
                "P":glyph=35'b11110_10001_10001_11110_10000_10000_10000;
                "R":glyph=35'b11110_10001_10001_11110_10100_10010_10001;
                "S":glyph=35'b01111_10000_10000_01110_00001_00001_11110;
                "T":glyph=35'b11111_00100_00100_00100_00100_00100_00100;
                "U":glyph=35'b10001_10001_10001_10001_10001_10001_01110;
                "V":glyph=35'b10001_10001_10001_10001_10001_01010_00100;
                "%":glyph=35'b11001_11010_00100_01000_10110_00110_00000;
                "X":glyph=35'b10001_10001_01010_00100_01010_10001_10001;
                "Y":glyph=35'b10001_10001_01010_00100_00100_00100_00100;
                "+":glyph=35'b00000_00100_00100_11111_00100_00100_00000;
                "-":glyph=35'b00000_00000_00000_11111_00000_00000_00000;
                "Q":glyph=35'b01110_10001_10001_10001_10101_10010_01101;
                "W":glyph=35'b10001_10001_10001_10101_10101_10101_01010;
                "Z":glyph=35'b11111_00001_00010_00100_01000_10000_11111;
                ":":glyph=35'b00000_00100_00100_00000_00100_00100_00000;
                ".":glyph=35'b00000_00000_00000_00000_00000_00110_00110;
                "/":glyph=35'b00001_00010_00010_00100_01000_01000_10000;
                "_":glyph=35'b00000_00000_00000_00000_00000_00000_11111;
                "(":glyph=35'b00010_00100_01000_01000_01000_00100_00010;
                ")":glyph=35'b01000_00100_00010_00010_00010_00100_01000;
                "[":glyph=35'b01110_01000_01000_01000_01000_01000_01110;
                "]":glyph=35'b01110_00010_00010_00010_00010_00010_01110;
                ">":glyph=35'b10000_01000_00100_00010_00100_01000_10000;
                default:glyph=0;
            endcase
        end
    endfunction
 reg [255:0] line;reg [23:0] color;reg overlay;reg [7:0] letter;reg [34:0] shape;
 integer row,ci,fx,fy,k,level,width,col;reg text_on;
 always @*begin
  overlay=x<704&&(page==8||page==9);color=24'h09111d;line=0;row=0;ci=0;fx=0;fy=0;k=0;level=0;width=0;col=0;text_on=0;letter=32;shape=0;
  if(page==8)begin
   if(x>=32&&x<672&&y>=64&&y<272)begin
    row=(y-64)/26;ci=(x-32)>>4;fx=(x-32)&15;fy=(y-64)%26;text_on=fy<14&&ci<32;
    case(row)
     0:line="VERIFY D13 - PURE HDL LIVE      ";
     1:begin line="FS NOM 48000 MEAS ----- HZ      ";if(st[117])for(k=0;k<5;k=k+1)line[(31-18-k)*8+:8]=decchar(decimals[0+:40],4-k);end
     2:begin line="LIVE VOICES 00 TEST UNITS 00    ";line[(31-12)*8+:8]=small_digit(st[11:6],1);line[(31-13)*8+:8]=small_digit(st[11:6],0);line[(31-26)*8+:8]=small_digit(st[5:0],1);line[(31-27)*8+:8]=small_digit(st[5:0],0);end
     3:begin line="LAST/MAX CYC 0000/0000          ";for(k=0;k<4;k=k+1)begin line[(31-13-k)*8+:8]=decchar(decimals[40+:40],3-k);line[(31-18-k)*8+:8]=decchar(decimals[80+:40],3-k);end end
     4:begin line="GATE->DAC ------ CYC @50MHZ     ";if(st[116])for(k=0;k<6;k=k+1)line[(31-10-k)*8+:8]=decchar(decimals[120+:40],5-k);end
     5:line="ANALOG LAT: MEASURE EXTERNALLY  ";
     6:begin line="FAULT 00 PCM PEAK 00000         ";line[(31-6)*8+:8]=hexchar(st[115:112]);line[(31-7)*8+:8]=hexchar(st[111:108]);for(k=0;k<5;k=k+1)line[(31-18-k)*8+:8]=decchar(decimals[160+:40],4-k);end
     7:line="TEST: 375HZ STEPS, MAX 12000HZ  ";
     default:line=0;
    endcase
   end
   for(k=0;k<6;k=k+1)if(x>=32+k*108&&x<128+k*108&&y>=288&&y<336)begin
    case(k)0:level=1;1:level=4;2:level=8;3:level=16;4:level=28;default:level=32;endcase
    color=chosen==level?24'h24654f:24'h193149;
    if(x>=48+k*108&&x<112+k*108&&y>=304&&y<318)begin
     text_on=1;line={small_digit(level,1),small_digit(level,0)," UNITS                        "};ci=(x-(48+k*108))>>4;fx=(x-(48+k*108))&15;fy=y-304;
    end
   end
   if(x>=32&&x<224&&y>=352&&y<408)begin
    color=running?24'h863f4c:24'h24654f;
    if(x>=48&&x<208&&y>=372&&y<386)begin line=running?"STOP TEST                       ":"START TEST                      ";text_on=1;ci=(x-48)>>4;fx=(x-48)&15;fy=y-372;end
   end
   if(x>=256&&x<672&&y>=356&&y<370)begin line="STOP TEST TO PLAY LIVE KEYS     ";text_on=1;ci=(x-256)>>4;fx=(x-256)&15;fy=y-356;end
   if(x>=256&&x<672&&y>=388&&y<402)begin
    line="USB ERR 00 / SKIP 00            ";line[(31-8)*8+:8]=hexchar(extension[239:236]);line[(31-9)*8+:8]=hexchar(extension[235:232]);
    line[(31-18)*8+:8]=hexchar(extension[231:228]);line[(31-19)*8+:8]=hexchar(extension[227:224]);
    text_on=1;ci=(x-256)>>4;fx=(x-256)&15;fy=y-388;
   end
   if(x>=32&&x<672&&y>=432&&y<446)begin line="I2S J13: 1 BCLK 2 WS 3 DATA     ";text_on=1;ci=(x-32)>>4;fx=(x-32)&15;fy=y-432;end
  end
  if(page==9)begin
   if(x>=32&&x<672&&y>=32&&y<46)begin line="EFFECTS D13 - HARDWARE DSP      ";text_on=1;ci=(x-32)>>4;fx=(x-32)&15;fy=y-32;end
   for(k=0;k<3;k=k+1)begin
    if(x>=32&&x<176&&y>=96+k*104&&y<160+k*104)begin
     color=enabled[k]?24'h24654f:24'h193149;
     if(x>=40&&x<168&&y>=112+k*104&&y<126+k*104)begin
      case(k)0:line="REVERB                          ";1:line="ECHO                            ";default:line="CHORUS                          ";endcase
      text_on=1;ci=(x-40)>>4;fx=(x-40)&15;fy=y-(112+k*104);
     end
     if(x>=64&&x<144&&y>=136+k*104&&y<150+k*104)begin line=enabled[k]?"ON                              ":"OFF                             ";text_on=1;ci=(x-64)>>4;fx=(x-64)&15;fy=y-(136+k*104);end
    end
    level=levels[k*7+:7];width=level*4;
    if(x>=208&&x<608&&y>=112+k*104&&y<152+k*104)color=(x-208<width)?24'h32a8b2:24'h20364d;
    if(x>=608&&x<672&&y>=124+k*104&&y<138+k*104)begin line={small_digit(level,2),small_digit(level,1),small_digit(level,0),"%                            "};text_on=1;ci=(x-608)>>4;fx=(x-608)&15;fy=y-(124+k*104);end
   end
   if(x>=32&&x<672&&y>=432&&y<446)begin line="PERSISTENT / REC INCLUDES FX    ";text_on=1;ci=(x-32)>>4;fx=(x-32)&15;fy=y-432;end
  end
  if(text_on&&ci>=0&&ci<32)letter=line[(31-ci)*8+:8];
 end
 reg [23:0] color_q,color_qq;reg overlay_q,overlay_qq,text_q;reg [7:0] letter_q;reg [3:0] fx_q,fy_q;
 wire [34:0] registered_glyph=glyph(letter_q);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin color_q<=0;color_qq<=0;overlay_q<=0;overlay_qq<=0;text_q<=0;letter_q<=32;fx_q<=0;fy_q<=0;end
  else begin
   color_q<=color;letter_q<=letter;fx_q<=fx;fy_q<=fy;text_q<=text_on&&ci>=0&&ci<32&&fx<10&&fy<14;
   color_qq<=(text_q&&registered_glyph[34-((fy_q>>1)*5+(fx_q>>1))])?24'hd9e2ef:color_q;
   overlay_q<=overlay;overlay_qq<=overlay_q;
  end
 end
 assign rgb=overlay_qq?color_qq:base_rgb;
endmodule

// 一套32步double-dabble格式化五个数值；完成后整体提交，避免一帧文字撕裂。
module validation_decimal_formatter(input wire clk,rst_n,start,input wire [191:0] status,output reg [199:0] digits);
 reg [191:0] held;reg [2:0] field;reg [5:0] bit_index;reg busy;reg [31:0] binary;
 reg [39:0] bcd;reg [199:0] staging;reg [39:0] adjusted;integer n;
 always @*begin adjusted=bcd;for(integer k=0;k<10;k=k+1)if(bcd[k*4+:4]>=5)adjusted[k*4+:4]=bcd[k*4+:4]+4'd3;end
 wire [39:0] shifted={adjusted[38:0],binary[31]};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin digits<=0;held<=0;field<=0;bit_index<=0;busy<=0;binary<=0;bcd<=0;staging<=0;end
  else if(start&&!busy)begin held<=status;field<=0;bit_index<=0;busy<=1;binary<={16'd0,status[27:12]};bcd<=0;end
  else if(busy)begin
   bcd<=shifted;binary<=binary<<1;bit_index<=bit_index+1'b1;
   if(bit_index==31)begin
    staging[field*40+:40]<=shifted;bcd<=0;bit_index<=0;field<=field+1'b1;
    case(field)0:binary<={16'd0,held[43:28]};1:binary<={16'd0,held[59:44]};2:binary<=held[91:60];3:binary<={16'd0,held[107:92]};default:binary<=0;endcase
    if(field==4)begin digits<={shifted,staging[159:0]};busy<=0;end
   end
  end
 end
endmodule
