`timescale 1ns/1ps
// 800x480界面；UI状态和音频/按键快照只在垂直消隐期原子更新。
module piano_ui_renderer_reference #(parameter integer ENABLE_USB_DIAG=0)(
    input wire clk,rst_n,frame_tick,snapshot_valid,input wire [298:0] snapshot,
    input wire [9:0] x,y,input wire hs,vs,de,
    output reg hs_out,vs_out,de_out,output reg [23:0] rgb,
    input wire [71:0] usb_diag                    // 已在消隐期握手换入的诊断快照。
);
    reg [255:0] target,shown,peaks;reg [27:0] keys;
    reg [1:0] page;reg [6:0] volume;reg connected;
    reg signed [3:0] transpose;reg dark;reg [2:0] peak_timer;
    integer k;reg [9:0] smooth_value;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin target<=0;shown<=0;peaks<=0;keys<=0;page<=1;volume<=25;
            connected<=0;transpose<=0;dark<=0;peak_timer<=0;end
        else begin
            if(snapshot_valid) begin
                target<=snapshot[255:0];keys<=snapshot[283:256];transpose<=snapshot[287:284];
                dark<=snapshot[288];page<=snapshot[290:289];volume<=snapshot[297:291];connected<=snapshot[298];
            end
            if(frame_tick) begin
                peak_timer<=peak_timer==5 ? 0 : peak_timer+1'b1;
                for(k=0;k<32;k=k+1) begin
                    if(target[k*8+:8]>shown[k*8+:8]) smooth_value=({2'b0,shown[k*8+:8]}+{2'b0,target[k*8+:8]}+1)>>1;
                    else smooth_value=({2'b0,shown[k*8+:8]}*3+{2'b0,target[k*8+:8]})>>2;
                    shown[k*8+:8]<=smooth_value[7:0];
                    if(smooth_value>peaks[k*8+:8]) peaks[k*8+:8]<=smooth_value[7:0];
                    else if(peak_timer==5) peaks[k*8+:8]<=peaks[k*8+:8]>3 ? peaks[k*8+:8]-3 : 0;
                end
            end
        end
    end
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
                default:glyph=0;
            endcase
        end
    endfunction

    // D2两行固定位置诊断文字；数值为十六进制，避免像素路径引入十进制除法。
    function [7:0] hexchar(input [3:0] n);
        begin hexchar=n<10 ? "0"+n : "A"+(n-10);end
    endfunction
    function [7:0] diag_char(input bottom,input [6:0] index,input [71:0] d);
        begin
            diag_char=32;
            if(!bottom) case(index)
                0:diag_char="U";
                1:diag_char="S";
                2:diag_char="B";
                3:diag_char=" ";
                4:diag_char="D";
                5:diag_char="7";
                6:diag_char=" ";
                7:diag_char="C";
                8:diag_char="0"+d[64];
                9:diag_char=" ";
                10:diag_char="L";
                11:diag_char="0"+d[65];
                12:diag_char=" ";
                13:diag_char="R";
                14:diag_char="0"+d[66];
                15:diag_char=" ";
                16:diag_char="B";
                17:diag_char="0"+d[63];
                18:diag_char=" ";
                19:diag_char="J";
                20:diag_char="0"+d[60];
                21:diag_char=" ";
                22:diag_char="T";
                23:diag_char="0"+d[61];
                24:diag_char=" ";
                25:diag_char="X";
                26:diag_char="0"+d[62];
                27:diag_char=" ";
                28:diag_char="S";
                29:diag_char=hexchar(d[7:4]);
                30:diag_char=hexchar(d[3:0]);
                31:diag_char=" ";
                32:diag_char="P";
                33:diag_char=hexchar(d[11:8]);
                34:diag_char=" ";
                35:diag_char="H";
                36:diag_char="0"+d[67];
                37:diag_char=" ";
                38:diag_char="A";
                39:diag_char="0"+d[68]; // 主机已长按启用。
                40:diag_char=" ";
                41:diag_char="D";
                42:diag_char="0"+d[69]; // USB1原始同步D+。
                43:diag_char="0"+d[70]; // USB1原始同步D-。
                44:diag_char=" ";
                45:diag_char="O";
                46:diag_char="0"+d[71]; // FPGA当前是否正在驱动USB1。
                47:diag_char=" ";
                48:diag_char="U";
                49:diag_char="2";
                50:diag_char="0"+d[13]; // USB2 D+，独立系统时钟同步。
                51:diag_char="0"+d[12]; // USB2 D-，与主机复位无关。
                default:diag_char=32;
            endcase
            else case(index)
                0:diag_char="E";
                1:diag_char="R";
                2:diag_char="R";
                3:diag_char=hexchar(d[31:28]);
                4:diag_char=" ";
                5:diag_char="A";
                6:diag_char="T";
                7:diag_char=hexchar(d[23:20]);
                8:diag_char=hexchar(d[19:16]);
                9:diag_char=" ";
                10:diag_char="P";
                11:diag_char=hexchar(d[27:24]);
                12:diag_char=" ";
                13:diag_char="T";
                14:diag_char="R";
                15:diag_char=hexchar(d[35:32]);
                16:diag_char=" ";
                17:diag_char="L";
                18:diag_char="E";
                19:diag_char="N";
                20:diag_char=hexchar(d[43:40]);
                21:diag_char=hexchar(d[39:36]);
                22:diag_char=" ";
                23:diag_char="R";
                24:diag_char="X";
                25:diag_char=hexchar(d[51:48]);
                26:diag_char=hexchar(d[47:44]);
                27:diag_char=" ";
                28:diag_char="N";
                29:diag_char=hexchar(d[59:56]);
                30:diag_char=hexchar(d[55:52]);
                default:diag_char=32;
            endcase
        end
    endfunction

    function [7:0] string_char;
        input [127:0] text;input [6:0] index;
        begin string_char=(index<16) ? text[(4'd15-index[3:0])*8+:8] : 8'd32;end
    endfunction
    // 坐标只有10位，显式限制运算位宽；避免像素路径推导出32位通用除法器。
    function [6:0] div12(input [9:0] v);begin div12=v/10'd12;end endfunction
    function [3:0] mod12(input [9:0] v);begin mod12=v%10'd12;end endfunction
    function [5:0] div21(input [9:0] v);begin div21=v/10'd21;end endfunction
    function [4:0] mod21(input [9:0] v);begin mod21=v%10'd21;end endfunction
    function [5:0] div28(input [9:0] v);begin div28=v/10'd28;end endfunction
    function [4:0] mod28(input [9:0] v);begin mod28=v%10'd28;end endfunction
    function [4:0] mod23(input [9:0] v);begin mod23=v%10'd23;end endfunction
    function [6:0] cell_offset(input [9:0] position,origin);begin cell_offset=position-origin;end endfunction
    function [2:0] glyph_half(input [9:0] position,origin);
        reg [9:0] d;begin d=position-origin;glyph_half=d[3:1];end
    endfunction
    wire [9:0] dx16=x-10'd16,dx128=x-10'd128,dx432=x-10'd432;
    wire [15:0] volume_product=volume*16'd336;
    wire [8:0] volume_height=volume_product/16'd100;
    wire [3:0] volume_tens=(volume/7'd10)%7'd10,volume_ones=volume%7'd10;
    reg [23:0] color,key_color;reg [7:0] letter;
    integer row,col,idx,bh,ph,fx,fy,ci,tx,ty,base_y,pitch,local_x,local_y;
    reg [127:0] text;integer trans_abs,c,r;reg [5:0] font_index;
    always @* begin
        color=24'h09111d;key_color=24'h32d39a;letter=32;
        row=0;col=0;idx=0;bh=0;ph=0;fx=0;fy=0;ci=0;tx=0;ty=0;base_y=0;pitch=1;local_x=0;local_y=0;text=0;
        trans_abs=transpose[3] ? -$signed(transpose) : transpose;
        if(x>=704) color=24'h142339;
        if(page==0) begin
            if(y>=144 && y<336 && x>=80 && x<336) color=24'h153c53;
            if(y>=144 && y<336 && x>=384 && x<640) color=24'h223655;
            // 两个应用的几何图标：频谱柱与琴键。
            if(y>=184 && y<248 && x>=128 && x<288 && mod28(dx128)<18 && y>=248-(div28(dx128)+1)*10) color=24'h32d39a;
            if(y>=184 && y<248 && x>=432 && x<592 && mod23(dx432)<19) color=24'hd9e2ef;
        end
        if(page==1 && x>=16 && x<688 && y>=56 && y<280) begin
            col=div21(dx16);local_x=mod21(dx16);
            bh=(shown[col*8+:8]*220)>>8;ph=(peaks[col*8+:8]*220)>>8;
            if(y==112 || y==168 || y==224 || y==278) color=24'h1b2b3d;
            if(local_x<15 && bh!=0 && y>=278-bh && y<278) color={8'd80,8'd210,8'd130};
            if(local_x<15 && ph!=0 && y>=278-ph && y<280-ph) color=24'hffffff;
        end
        if(page!=0) begin
            base_y=(page==1) ? 304 : 96;pitch=(page==1) ? 28 : 80;
            if(x>=16 && x<688 && y>=base_y && y<416) begin
                // 每个矩形直接比较，不在像素组合路径中使用可变分母pitch。
                for(c=0;c<7;c=c+1) if(x>=16+c*96 && x<112+c*96) begin col=c;local_x=cell_offset(x,16+c*96);end
                for(r=0;r<4;r=r+1) begin
                    if(page==1 && y>=304+r*28 && y<332+r*28) begin row=r;local_y=cell_offset(y,304+r*28);end
                    if(page==2 && y>=96+r*80 && y<176+r*80) begin row=r;local_y=cell_offset(y,96+r*80);end
                end
                idx=row*7+col;
                case(row) 0:key_color=24'h32d3b8;1:key_color=24'h4794ed;2:key_color=24'hb978ef;default:key_color=24'heab15b;endcase
                if(local_x<90 && local_y<pitch-4) color=keys[idx] ? key_color : 24'hd9e2ef;
                if(local_y>=(pitch-14)/2 && local_y<(pitch-14)/2+14 && local_x>=32 && local_x<56) begin
                    fx=(local_x<44) ? glyph_half(local_x,32) : glyph_half(local_x,44);
                    fy=glyph_half(local_y,page==1?7:33);
                    if(local_x<44) case(col) 0:letter="C";1:letter="D";2:letter="E";3:letter="F";4:letter="G";5:letter="A";default:letter="B";endcase
                    else letter="3"+row;
                end
            end
        end
        // 页面标题与Home应用标签。
        if(x>=16 && x<688 && y>=16 && y<30) begin
            text=(page==0) ? "PIANO HOME      " : (page==1) ? "PIANO SPECTRUM  " : "TOUCH KEYBOARD  ";
            ci=div12(dx16);letter=string_char(text,ci);fx=mod12(dx16)>>1;fy=glyph_half(y,16);
        end
        if(page==0 && y>=280 && y<294) begin
            if(x>=160 && x<256) begin letter=string_char("SPECTRUM        ",div12(x-10'd160));fx=mod12(x-10'd160)>>1;fy=glyph_half(y,280);end
            if(x>=464 && x<560) begin letter=string_char("KEYBOARD        ",div12(x-10'd464));fx=mod12(x-10'd464)>>1;fy=glyph_half(y,280);end
        end
        if(x>=16 && x<352 && y>=446 && y<460) begin
            ci=div12(dx16);fx=mod12(dx16)>>1;fy=glyph_half(y,446);
            case(ci) 0:letter="T";1:letter="R";2:letter="A";3:letter="N";4:letter="S";
                6:letter=transpose[3] ? "-" : "+";7:letter="0"+trans_abs;
                10:letter=dark ? "D" : "B";11:letter=dark ? "A" : "R";12:letter=dark ? "R" : "I";13:letter=dark ? "K" : "G";
                14:letter=dark ? " " : "H";15:letter=dark ? " " : "T";
                default:letter=32;endcase
        end
        // 所有页面共用同一音量条，顶部100%，底部0%。
        if(x>=736 && x<776 && y>=64 && y<=400) begin
            color=24'h263d54;
            if(y>=400-volume_height) color=24'h32d39a;
            if(y>=398-volume_height && y<=402-volume_height) color=24'hffffff;
        end
        if(x>=736 && x<772 && y>=16 && y<30) begin
            letter=string_char("VOL             ",div12(x-10'd736));fx=mod12(x-10'd736)>>1;fy=glyph_half(y,16);
        end
        if(x>=726 && x<786 && y>=412 && y<426) begin
            ci=div12(x-10'd726);fx=mod12(x-10'd726)>>1;fy=glyph_half(y,412);
            case(ci) 0:letter=volume==100 ? "1" : " ";1:letter="0"+volume_tens;2:letter="0"+volume_ones;3:letter="%";default:letter=32;endcase
        end
        if(x>=704 && x<792 && y>=432 && y<476) color=24'h265faa;
        if(x>=724 && x<772 && y>=448 && y<462) begin
            letter=string_char("HOME            ",div12(x-10'd724));fx=mod12(x-10'd724)>>1;fy=glyph_half(y,448);
        end
        // 连接灯只表示触摸报告通路就绪，不能用视频连接冒充触摸成功。
        if(x>=672 && x<688 && y>=16 && y<30) color=connected ? 24'h32d39a : 24'hc85d47;
        // 使用标题下方和底部原空白行，三页均可拍照；不覆盖琴键/音量/Home命中区域。
        if(ENABLE_USB_DIAG && x>=16 && x<688 && ((y>=32 && y<46) || (y>=466 && y<480))) begin
            color=24'h09111d;ci=div12(dx16);fx=mod12(dx16)>>1;
            fy=glyph_half(y,y>=466?466:32);letter=diag_char(y>=466,ci,usb_diag);
        end
        font_index=6'd34-fy[2:0]*6'd5-fx[2:0];
        if(!de) color=0;
    end
    // 两级像素流水：第一级做几何/字符选择，第二级做字形ROM与颜色覆盖。
    // HS/VS/DE同步延迟两级，每拍仍输出一个像素，画面与刷新时序不变。
    reg [23:0] background_d;reg [7:0] letter_d;reg [5:0] index_d;
    reg font_valid_d,ink_dark_d,hs_d,vs_d,de_d;
    wire [34:0] font_d=glyph(letter_d);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            rgb<=0;hs_out<=1;vs_out<=0;de_out<=0;background_d<=0;letter_d<=32;index_d<=0;
            font_valid_d<=0;ink_dark_d<=0;hs_d<=1;vs_d<=0;de_d<=0;
        end else begin
            background_d<=color;letter_d<=letter;index_d<=font_index;
            font_valid_d<=fx>=0 && fx<5 && fy>=0 && fy<7;
            ink_dark_d<=page!=0 && x<688 && y>=base_y && y<416;
            hs_d<=hs;vs_d<=vs;de_d<=de;
            rgb<=!de_d ? 24'd0 : ((font_valid_d && font_d[index_d]) ? (ink_dark_d?24'h09111d:24'he6edf5) : background_d);
            hs_out<=hs_d;vs_out<=vs_d;de_out<=de_d;
        end
    end
endmodule
