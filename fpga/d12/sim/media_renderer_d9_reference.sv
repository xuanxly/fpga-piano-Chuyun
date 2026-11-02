`timescale 1ns/1ps
// 新应用只覆盖需要改变的像素；旧频谱、旧大键盘、双柱及HS/VS/DE仍保持原两拍流水。
module media_renderer_d9_reference #(parameter integer ENABLE_USB_DIAG=1)(
    input wire clk,rst_n,frame_tick,snapshot_valid,input wire [298:0] snapshot,
    input wire [2210:0] media_snapshot,input wire [9:0] x,y,input wire hs,vs,de,
    output wire hs_out,vs_out,de_out,output wire [23:0] rgb,input wire [71:0] usb_diag,
    output reg [5:0] text_address,input wire [31:0] text_data);
    wire [23:0] base_rgb;
    piano_ui_renderer #(.ENABLE_USB_DIAG(ENABLE_USB_DIAG)) u_base(.clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),
        .snapshot_valid(snapshot_valid),.snapshot(snapshot),.x(x),.y(y),.hs(hs),.vs(vs),.de(de),
        .hs_out(hs_out),.vs_out(vs_out),.de_out(de_out),.rgb(base_rgb),.usb_diag(usb_diag));
    wire [2:0] page=media_snapshot[2178:2176],rec_state=media_snapshot[2052:2050],play_state=media_snapshot[2055:2053];
    wire [15:0] rec_seconds=media_snapshot[2095:2080],play_seconds=media_snapshot[2111:2096],duration=media_snapshot[2127:2112];
    wire [7:0] file_count=media_snapshot[2135:2128],msg=media_snapshot[2071:2064];
    wire [7:0] progress_percent=media_snapshot[2063:2056];
    wire [15:0] progress_product=progress_percent*16'd608;
    wire [9:0] progress_width=(progress_product+16'd50)/16'd100;
    wire [27:0] keys=snapshot[283:256];
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
                default:glyph=0;
            endcase
        end
    endfunction
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
                5:diag_char="9";
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
    function [6:0] div12(input [9:0] v);begin div12=v/10'd12;end endfunction
    function [3:0] mod12(input [9:0] v);begin mod12=v%10'd12;end endfunction
    function [2:0] glyph_half(input [9:0] position,origin);
        reg [9:0] d;begin d=position-origin;glyph_half=d[3:1];end
    endfunction
    function [7:0] upper_char(input [7:0] v);
        begin upper_char=(v>=97&&v<=122)?v-8'd32:v;end
    endfunction
    function [7:0] time_char(input [15:0] seconds,input integer n);
        begin case(n)
            0:time_char="0"+((seconds/16'd600)%10);
            1:time_char="0"+((seconds/16'd60)%10);
            2:time_char=":";
            3:time_char="0"+((seconds%16'd60)/10);
            4:time_char="0"+(seconds%10);
            default:time_char=32;
        endcase end
    endfunction
    function [127:0] message_text(input [7:0] m);
        begin case(m)
            0:message_text="READY           ";1:message_text="NO CARD         ";2:message_text="MOUNT ERROR     ";
            3:message_text="RECORD SAVED    ";4:message_text="END RECORD FIRST";5:message_text="UNSUPPORTED     ";
            6:message_text="CARD IO ERROR   ";7:message_text="DECODE ERROR    ";8:message_text="REC OVERFLOW    ";
            9:message_text="PLAY UNDERFLOW  ";10:message_text="FIVE MIN SAVED  ";11:message_text="LOADING         ";
            12:message_text="EMPTY FOLDER    ";13:message_text="CARD REMOVED    ";14:message_text="NO MEMORY       ";
            default:message_text="MEDIA STARTING  ";
        endcase end
    endfunction
    reg [23:0] color,key_color;reg [7:0] letter;reg [127:0] text;
    integer fx,fy,ci,c,r,row,col,lx,ly,idx;
    reg overlay,dark_ink,text_select;reg [1:0] text_lane;
    always @*begin
        overlay=x<704&&(page==0||page>=3);dark_ink=0;color=24'h09111d;letter=32;fx=0;fy=0;ci=0;
        text=0;row=0;col=0;lx=0;ly=0;idx=0;key_color=0;text_select=0;text_lane=0;text_address=0;
        if(page==0)begin
            if(x>=80&&x<336&&y>=96&&y<232)color=24'h153c53;
            if(x>=384&&x<640&&y>=96&&y<232)color=24'h223655;
            if(x>=80&&x<336&&y>=256&&y<392)color=24'h493040;
            if(x>=384&&x<640&&y>=256&&y<392)color=24'h4b4325;
            for(c=0;c<5;c=c+1)if(x>=132+c*28&&x<150+c*28&&y>=176-(c+1)*10&&y<176)color=24'h32d39a;
            for(c=0;c<7;c=c+1)if(x>=432+c*22&&x<450+c*22&&y>=128&&y<176)color=24'hd9e2ef;
            if(x>=176&&x<240&&y>=280&&y<328)color=24'hd96464;
            if(x>=448&&x<576&&y>=286&&y<330)color=24'heab15b;
            if(x>=448&&x<496&&y>=274&&y<286)color=24'heab15b;
            if(y>=200&&y<214)begin
                if(x>=160&&x<256)begin letter=string_char("SPECTRUM        ",div12(x-10'd160));fx=mod12(x-10'd160)>>1;fy=glyph_half(y,200);end
                if(x>=464&&x<560)begin letter=string_char("KEYBOARD        ",div12(x-10'd464));fx=mod12(x-10'd464)>>1;fy=glyph_half(y,200);end
            end
            if(y>=356&&y<370)begin
                if(x>=160&&x<256)begin letter=string_char("RECORDER        ",div12(x-10'd160));fx=mod12(x-10'd160)>>1;fy=glyph_half(y,356);end
                if(x>=480&&x<540)begin letter=string_char("FILES           ",div12(x-10'd480));fx=mod12(x-10'd480)>>1;fy=glyph_half(y,356);end
            end
        end
        if(page==3)begin
            for(c=0;c<7;c=c+1)for(r=0;r<4;r=r+1)if(x>=16+c*96&&x<106+c*96&&y>=96+r*60&&y<150+r*60)begin
                col=c;row=r;lx=x-(16+c*96);ly=y-(96+r*60);idx=r*7+c;
                case(r)0:key_color=24'h32d3b8;1:key_color=24'h4794ed;2:key_color=24'hb978ef;default:key_color=24'heab15b;endcase
                color=keys[idx]?key_color:24'hd9e2ef;dark_ink=1;
                if(lx>=32&&lx<56&&ly>=20&&ly<34)begin
                    fx=lx<44?glyph_half(lx,32):glyph_half(lx,44);fy=glyph_half(ly,20);
                    if(lx<44)case(c)0:letter="C";1:letter="D";2:letter="E";3:letter="F";4:letter="G";5:letter="A";default:letter="B";endcase
                    else letter="3"+r;
                end
            end
            if(y>=368&&y<424)begin
                if(x>=64&&x<312)color=rec_state==1||rec_state==2?24'ha7364d:24'h286d52;
                if(x>=352&&x<624)color=rec_state==1||rec_state==2?24'h265faa:24'h263d54;
            end
            if(y>=388&&y<402)begin
                if(x>=100&&x<280)begin text=(rec_state==1||rec_state==2)?"END RECORDING   ":"RECORD          ";letter=string_char(text,div12(x-10'd100));fx=mod12(x-10'd100)>>1;fy=glyph_half(y,388);end
                if(x>=416&&x<560)begin text=rec_state==2?"CONTINUE        ":"PAUSE           ";letter=string_char(text,div12(x-10'd416));fx=mod12(x-10'd416)>>1;fy=glyph_half(y,388);end
            end
        end
        if(page==4)begin
            for(r=0;r<6;r=r+1)if(x>=16&&x<672&&y>=96+r*44&&y<136+r*44)begin
                color=r<file_count?24'h153044:24'h101d2b;
                if(x>=32&&x<416&&y>=109+r*44&&y<123+r*44)begin
                    ci=div12(x-10'd32);text_select=1;text_address=r*8+(ci>>2);text_lane=ci[1:0];fx=mod12(x-10'd32)>>1;fy=glyph_half(y,109+r*44);
                end
            end
            if(y>=376&&y<424)for(c=0;c<4;c=c+1)if(x>=16+c*160&&x<144+c*160)color=24'h265faa;
            if(y>=392&&y<406&&x>=32&&x<624)begin
                if(x<144)begin letter=string_char("UP              ",div12(x-10'd32));fx=mod12(x-10'd32)>>1;end
                else if(x>=192&&x<304)begin letter=string_char("PREV            ",div12(x-10'd192));fx=mod12(x-10'd192)>>1;end
                else if(x>=352&&x<464)begin letter=string_char("NEXT            ",div12(x-10'd352));fx=mod12(x-10'd352)>>1;end
                else if(x>=512)begin letter=string_char("REFRESH         ",div12(x-10'd512));fx=mod12(x-10'd512)>>1;end
                fy=glyph_half(y,392);
            end
            if(x>=16&&x<400&&y>=56&&y<70)begin ci=div12(x-10'd16);text_select=1;text_address=48+(ci>>2);text_lane=ci[1:0];fx=mod12(x-10'd16)>>1;fy=glyph_half(y,56);end
        end
        if(page==5)begin
            if(x>=48&&x<432&&y>=96&&y<110)begin ci=div12(x-10'd48);text_select=1;text_address=56+(ci>>2);text_lane=ci[1:0];fx=mod12(x-10'd48)>>1;fy=glyph_half(y,96);end
            if(x>=48&&x<656&&y>=288&&y<320)begin color=24'h263d54;if(x<48+progress_width)color=24'h4794ed;end
            if(y>=224&&y<268)begin if(x>=48&&x<208)color=24'ha7364d;if(x>=240&&x<400)color=24'h265faa;end
            if(y>=352&&y<416)for(c=0;c<3;c=c+1)if(x>=48+c*192&&x<208+c*192)color=24'h265faa;
            if(y>=240&&y<254)begin
                if(x>=80&&x<152)begin letter=string_char("STOP            ",div12(x-10'd80));fx=mod12(x-10'd80)>>1;end
                if(x>=264&&x<360)begin letter=string_char("FILES           ",div12(x-10'd264));fx=mod12(x-10'd264)>>1;end
                fy=glyph_half(y,240);
            end
            if(y>=376&&y<390)begin
                if(x>=80&&x<176)begin letter=string_char("PREV            ",div12(x-10'd80));fx=mod12(x-10'd80)>>1;end
                if(x>=264&&x<384)begin text=play_state==2?"PLAY            ":"PAUSE           ";letter=string_char(text,div12(x-10'd264));fx=mod12(x-10'd264)>>1;end
                if(x>=464&&x<560)begin letter=string_char("NEXT            ",div12(x-10'd464));fx=mod12(x-10'd464)>>1;end
                fy=glyph_half(y,376);
            end
            if(y>=144&&y<158)begin
                if(x>=48&&x<108)begin letter=time_char(play_seconds,div12(x-10'd48));fx=mod12(x-10'd48)>>1;end
                if(x>=588&&x<648)begin letter=time_char(duration,div12(x-10'd588));fx=mod12(x-10'd588)>>1;end
                fy=glyph_half(y,144);
            end
        end
        if(page!=4&&page!=5&&(rec_state==1||rec_state==2)&&x>=16&&x<220&&y>=56&&y<70)begin
            ci=div12(x-10'd16);fx=mod12(x-10'd16)>>1;fy=glyph_half(y,56);
            if(ci<6)letter=string_char(rec_state==2?"PAUSED          ":"REC             ",ci);else letter=time_char(rec_seconds,ci-6);
        end
        if(x>=16&&x<400&&y>=16&&y<30)begin
            text=page==0?"PIANO HOME      ":page==3?"RECORDER        ":page==4?"FILE MANAGER    ":"AUDIO PLAYER    ";
            letter=string_char(text,div12(x-10'd16));fx=mod12(x-10'd16)>>1;fy=glyph_half(y,16);
        end
        if(x>=16&&x<400&&y>=446&&y<460)begin
            letter=string_char(message_text(msg),div12(x-10'd16));fx=mod12(x-10'd16)>>1;fy=glyph_half(y,446);
        end
        if(ENABLE_USB_DIAG&&x>=16&&x<688&&((y>=32&&y<46)||(y>=466&&y<480)))begin
            ci=div12(x-10'd16);fx=mod12(x-10'd16)>>1;fy=glyph_half(y,y>=466?466:32);letter=diag_char(y>=466,ci,usb_diag);
        end
        // 播放页只允许音量调节；音调柄与数值置灰，不改变保存的琴音移调值。
        if(page==5&&x>=754&&x<800&&y>=48&&y<426)begin
            overlay=1;color=24'h142339;letter=32;dark_ink=0;
            if(x>=760&&x<792&&y>=64&&y<=400)color=24'h263d54;
            if(x>=760&&x<792&&y>=230&&y<=234)color=24'h627080;
            if(x>=764&&x<788&&y>=412&&y<426)begin letter="-";fx=mod12(x-10'd764)>>1;fy=glyph_half(y,412);end
        end
    end
    reg [23:0] background_d,overlay_rgb;reg [7:0] letter_d;reg [5:0] index_d;
    reg valid_d,ink_d,de_d,en_d,en_q;
    reg text_select_d;reg [1:0] text_lane_d;
    wire [7:0] ram_letter=text_data[text_lane_d*8+:8];
    wire [34:0] bits=glyph(text_select_d?upper_char(ram_letter):letter_d);
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin background_d<=0;overlay_rgb<=0;letter_d<=32;index_d<=0;valid_d<=0;ink_d<=0;de_d<=0;en_d<=0;en_q<=0;text_select_d<=0;text_lane_d<=0;end
        else begin
            background_d<=color;letter_d<=letter;text_select_d<=text_select;text_lane_d<=text_lane;index_d<=6'd34-fy[2:0]*6'd5-fx[2:0];
            valid_d<=fx>=0&&fx<5&&fy>=0&&fy<7;ink_d<=dark_ink;de_d<=de;en_d<=overlay;en_q<=en_d;
            overlay_rgb<=!de_d?24'd0:((valid_d&&bits[index_d])?(ink_d?24'h09111d:24'he6edf5):background_d);
        end
    end
    assign rgb=en_q?overlay_rgb:base_rgb;
endmodule
