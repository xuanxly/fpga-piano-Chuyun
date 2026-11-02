`timescale 1ns/1ps
// 新应用只覆盖需要改变的像素；旧频谱、旧大键盘、双柱及HS/VS/DE仍保持原两拍流水。
module media_ui_renderer #(parameter integer ENABLE_USB_DIAG=1)(
    input wire clk,rst_n,frame_tick,snapshot_valid,input wire [298:0] snapshot,
    input wire [2378:0] media_snapshot,input wire [9:0] x,y,input wire hs,vs,de,
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
    // 常数查表保持原8位输入全部256种结果，避免DSP吸收跨域快照寄存器。
    function [9:0] progress_pixels(input [7:0] percent);
        begin case(percent)
            8'd0:progress_pixels=10'd0;
            8'd1:progress_pixels=10'd6;
            8'd2:progress_pixels=10'd12;
            8'd3:progress_pixels=10'd18;
            8'd4:progress_pixels=10'd24;
            8'd5:progress_pixels=10'd30;
            8'd6:progress_pixels=10'd36;
            8'd7:progress_pixels=10'd43;
            8'd8:progress_pixels=10'd49;
            8'd9:progress_pixels=10'd55;
            8'd10:progress_pixels=10'd61;
            8'd11:progress_pixels=10'd67;
            8'd12:progress_pixels=10'd73;
            8'd13:progress_pixels=10'd79;
            8'd14:progress_pixels=10'd85;
            8'd15:progress_pixels=10'd91;
            8'd16:progress_pixels=10'd97;
            8'd17:progress_pixels=10'd103;
            8'd18:progress_pixels=10'd109;
            8'd19:progress_pixels=10'd116;
            8'd20:progress_pixels=10'd122;
            8'd21:progress_pixels=10'd128;
            8'd22:progress_pixels=10'd134;
            8'd23:progress_pixels=10'd140;
            8'd24:progress_pixels=10'd146;
            8'd25:progress_pixels=10'd152;
            8'd26:progress_pixels=10'd158;
            8'd27:progress_pixels=10'd164;
            8'd28:progress_pixels=10'd170;
            8'd29:progress_pixels=10'd176;
            8'd30:progress_pixels=10'd182;
            8'd31:progress_pixels=10'd188;
            8'd32:progress_pixels=10'd195;
            8'd33:progress_pixels=10'd201;
            8'd34:progress_pixels=10'd207;
            8'd35:progress_pixels=10'd213;
            8'd36:progress_pixels=10'd219;
            8'd37:progress_pixels=10'd225;
            8'd38:progress_pixels=10'd231;
            8'd39:progress_pixels=10'd237;
            8'd40:progress_pixels=10'd243;
            8'd41:progress_pixels=10'd249;
            8'd42:progress_pixels=10'd255;
            8'd43:progress_pixels=10'd261;
            8'd44:progress_pixels=10'd268;
            8'd45:progress_pixels=10'd274;
            8'd46:progress_pixels=10'd280;
            8'd47:progress_pixels=10'd286;
            8'd48:progress_pixels=10'd292;
            8'd49:progress_pixels=10'd298;
            8'd50:progress_pixels=10'd304;
            8'd51:progress_pixels=10'd310;
            8'd52:progress_pixels=10'd316;
            8'd53:progress_pixels=10'd322;
            8'd54:progress_pixels=10'd328;
            8'd55:progress_pixels=10'd334;
            8'd56:progress_pixels=10'd340;
            8'd57:progress_pixels=10'd347;
            8'd58:progress_pixels=10'd353;
            8'd59:progress_pixels=10'd359;
            8'd60:progress_pixels=10'd365;
            8'd61:progress_pixels=10'd371;
            8'd62:progress_pixels=10'd377;
            8'd63:progress_pixels=10'd383;
            8'd64:progress_pixels=10'd389;
            8'd65:progress_pixels=10'd395;
            8'd66:progress_pixels=10'd401;
            8'd67:progress_pixels=10'd407;
            8'd68:progress_pixels=10'd413;
            8'd69:progress_pixels=10'd420;
            8'd70:progress_pixels=10'd426;
            8'd71:progress_pixels=10'd432;
            8'd72:progress_pixels=10'd438;
            8'd73:progress_pixels=10'd444;
            8'd74:progress_pixels=10'd450;
            8'd75:progress_pixels=10'd456;
            8'd76:progress_pixels=10'd462;
            8'd77:progress_pixels=10'd468;
            8'd78:progress_pixels=10'd474;
            8'd79:progress_pixels=10'd480;
            8'd80:progress_pixels=10'd486;
            8'd81:progress_pixels=10'd492;
            8'd82:progress_pixels=10'd499;
            8'd83:progress_pixels=10'd505;
            8'd84:progress_pixels=10'd511;
            8'd85:progress_pixels=10'd517;
            8'd86:progress_pixels=10'd523;
            8'd87:progress_pixels=10'd529;
            8'd88:progress_pixels=10'd535;
            8'd89:progress_pixels=10'd541;
            8'd90:progress_pixels=10'd547;
            8'd91:progress_pixels=10'd553;
            8'd92:progress_pixels=10'd559;
            8'd93:progress_pixels=10'd565;
            8'd94:progress_pixels=10'd572;
            8'd95:progress_pixels=10'd578;
            8'd96:progress_pixels=10'd584;
            8'd97:progress_pixels=10'd590;
            8'd98:progress_pixels=10'd596;
            8'd99:progress_pixels=10'd602;
            8'd100:progress_pixels=10'd608;
            8'd101:progress_pixels=10'd614;
            8'd102:progress_pixels=10'd620;
            8'd103:progress_pixels=10'd626;
            8'd104:progress_pixels=10'd632;
            8'd105:progress_pixels=10'd638;
            8'd106:progress_pixels=10'd644;
            8'd107:progress_pixels=10'd651;
            8'd108:progress_pixels=10'd1;
            8'd109:progress_pixels=10'd7;
            8'd110:progress_pixels=10'd13;
            8'd111:progress_pixels=10'd20;
            8'd112:progress_pixels=10'd26;
            8'd113:progress_pixels=10'd32;
            8'd114:progress_pixels=10'd38;
            8'd115:progress_pixels=10'd44;
            8'd116:progress_pixels=10'd50;
            8'd117:progress_pixels=10'd56;
            8'd118:progress_pixels=10'd62;
            8'd119:progress_pixels=10'd68;
            8'd120:progress_pixels=10'd74;
            8'd121:progress_pixels=10'd80;
            8'd122:progress_pixels=10'd86;
            8'd123:progress_pixels=10'd92;
            8'd124:progress_pixels=10'd99;
            8'd125:progress_pixels=10'd105;
            8'd126:progress_pixels=10'd111;
            8'd127:progress_pixels=10'd117;
            8'd128:progress_pixels=10'd123;
            8'd129:progress_pixels=10'd129;
            8'd130:progress_pixels=10'd135;
            8'd131:progress_pixels=10'd141;
            8'd132:progress_pixels=10'd147;
            8'd133:progress_pixels=10'd153;
            8'd134:progress_pixels=10'd159;
            8'd135:progress_pixels=10'd165;
            8'd136:progress_pixels=10'd172;
            8'd137:progress_pixels=10'd178;
            8'd138:progress_pixels=10'd184;
            8'd139:progress_pixels=10'd190;
            8'd140:progress_pixels=10'd196;
            8'd141:progress_pixels=10'd202;
            8'd142:progress_pixels=10'd208;
            8'd143:progress_pixels=10'd214;
            8'd144:progress_pixels=10'd220;
            8'd145:progress_pixels=10'd226;
            8'd146:progress_pixels=10'd232;
            8'd147:progress_pixels=10'd238;
            8'd148:progress_pixels=10'd244;
            8'd149:progress_pixels=10'd251;
            8'd150:progress_pixels=10'd257;
            8'd151:progress_pixels=10'd263;
            8'd152:progress_pixels=10'd269;
            8'd153:progress_pixels=10'd275;
            8'd154:progress_pixels=10'd281;
            8'd155:progress_pixels=10'd287;
            8'd156:progress_pixels=10'd293;
            8'd157:progress_pixels=10'd299;
            8'd158:progress_pixels=10'd305;
            8'd159:progress_pixels=10'd311;
            8'd160:progress_pixels=10'd317;
            8'd161:progress_pixels=10'd324;
            8'd162:progress_pixels=10'd330;
            8'd163:progress_pixels=10'd336;
            8'd164:progress_pixels=10'd342;
            8'd165:progress_pixels=10'd348;
            8'd166:progress_pixels=10'd354;
            8'd167:progress_pixels=10'd360;
            8'd168:progress_pixels=10'd366;
            8'd169:progress_pixels=10'd372;
            8'd170:progress_pixels=10'd378;
            8'd171:progress_pixels=10'd384;
            8'd172:progress_pixels=10'd390;
            8'd173:progress_pixels=10'd396;
            8'd174:progress_pixels=10'd403;
            8'd175:progress_pixels=10'd409;
            8'd176:progress_pixels=10'd415;
            8'd177:progress_pixels=10'd421;
            8'd178:progress_pixels=10'd427;
            8'd179:progress_pixels=10'd433;
            8'd180:progress_pixels=10'd439;
            8'd181:progress_pixels=10'd445;
            8'd182:progress_pixels=10'd451;
            8'd183:progress_pixels=10'd457;
            8'd184:progress_pixels=10'd463;
            8'd185:progress_pixels=10'd469;
            8'd186:progress_pixels=10'd476;
            8'd187:progress_pixels=10'd482;
            8'd188:progress_pixels=10'd488;
            8'd189:progress_pixels=10'd494;
            8'd190:progress_pixels=10'd500;
            8'd191:progress_pixels=10'd506;
            8'd192:progress_pixels=10'd512;
            8'd193:progress_pixels=10'd518;
            8'd194:progress_pixels=10'd524;
            8'd195:progress_pixels=10'd530;
            8'd196:progress_pixels=10'd536;
            8'd197:progress_pixels=10'd542;
            8'd198:progress_pixels=10'd548;
            8'd199:progress_pixels=10'd555;
            8'd200:progress_pixels=10'd561;
            8'd201:progress_pixels=10'd567;
            8'd202:progress_pixels=10'd573;
            8'd203:progress_pixels=10'd579;
            8'd204:progress_pixels=10'd585;
            8'd205:progress_pixels=10'd591;
            8'd206:progress_pixels=10'd597;
            8'd207:progress_pixels=10'd603;
            8'd208:progress_pixels=10'd609;
            8'd209:progress_pixels=10'd615;
            8'd210:progress_pixels=10'd621;
            8'd211:progress_pixels=10'd628;
            8'd212:progress_pixels=10'd634;
            8'd213:progress_pixels=10'd640;
            8'd214:progress_pixels=10'd646;
            8'd215:progress_pixels=10'd652;
            8'd216:progress_pixels=10'd3;
            8'd217:progress_pixels=10'd9;
            8'd218:progress_pixels=10'd15;
            8'd219:progress_pixels=10'd21;
            8'd220:progress_pixels=10'd27;
            8'd221:progress_pixels=10'd33;
            8'd222:progress_pixels=10'd39;
            8'd223:progress_pixels=10'd45;
            8'd224:progress_pixels=10'd51;
            8'd225:progress_pixels=10'd57;
            8'd226:progress_pixels=10'd63;
            8'd227:progress_pixels=10'd69;
            8'd228:progress_pixels=10'd76;
            8'd229:progress_pixels=10'd82;
            8'd230:progress_pixels=10'd88;
            8'd231:progress_pixels=10'd94;
            8'd232:progress_pixels=10'd100;
            8'd233:progress_pixels=10'd106;
            8'd234:progress_pixels=10'd112;
            8'd235:progress_pixels=10'd118;
            8'd236:progress_pixels=10'd124;
            8'd237:progress_pixels=10'd130;
            8'd238:progress_pixels=10'd136;
            8'd239:progress_pixels=10'd142;
            8'd240:progress_pixels=10'd148;
            8'd241:progress_pixels=10'd155;
            8'd242:progress_pixels=10'd161;
            8'd243:progress_pixels=10'd167;
            8'd244:progress_pixels=10'd173;
            8'd245:progress_pixels=10'd179;
            8'd246:progress_pixels=10'd185;
            8'd247:progress_pixels=10'd191;
            8'd248:progress_pixels=10'd197;
            8'd249:progress_pixels=10'd203;
            8'd250:progress_pixels=10'd209;
            8'd251:progress_pixels=10'd215;
            8'd252:progress_pixels=10'd221;
            8'd253:progress_pixels=10'd228;
            8'd254:progress_pixels=10'd234;
            8'd255:progress_pixels=10'd240;
            default:progress_pixels=0;
        endcase end
    endfunction
    wire [9:0] progress_width=progress_pixels(progress_percent);
    wire [27:0] keys=snapshot[283:256];
    wire [2:0] selected_timbre=media_snapshot[2213:2211];
    wire [4:0] effects=media_snapshot[2218:2214];
    wire [159:0] game=media_snapshot[2378:2219];
    wire game_running=game[128],game_practice=game[130],game_waiting=game[131],game_complete=game[132];
    wire [27:0] guide=game[27:0]; // 与PCB4共用同一硬件提示掩码。
    wire usb_exported=msg==17||msg==18;
    function [127:0] app_name(input integer n);
        begin case(n)0:app_name="SPECTRUM        ";1:app_name="KEYBOARD        ";2:app_name="RECORDER        ";
            3:app_name="FILES           ";4:app_name="TIMBRE          ";default:app_name="GAME            ";endcase end
    endfunction
    function [127:0] timbre_name(input [2:0] n);
        begin case(n)
            1:timbre_name="E-PIANO         ";2:timbre_name="ORGAN           ";
            3:timbre_name="GUITAR          ";4:timbre_name="STRINGS         ";
            default:timbre_name="PIANO           ";
        endcase end
    endfunction
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
    function [7:0] text_byte;
        input [127:0] text;input [6:0] index;
        begin text_byte=(index<16) ? text[(4'd15-index[3:0])*8+:8] : 8'd32;end
    endfunction
    // 第一拍只选择文本和字符序号，第二拍再取字符，保持原两拍RGB/同步延迟。
    function [143:0] string_char;
        input [127:0] text;input [6:0] index;
        begin string_char={1'b1,text,index,8'd0};end
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
            12:message_text="EMPTY FOLDER    ";13:message_text="CARD REMOVED    ";14:message_text="NO MEMORY       ";15:message_text="BAD CHART       ";16:message_text="USB LINK WAIT   ";17:message_text="USB DISK ACTIVE ";18:message_text="UNPLUG USB FIRST";
            default:message_text="MEDIA STARTING  ";
        endcase end
    endfunction
    reg [23:0] color,key_color;reg [143:0] letter;reg [127:0] text;
    integer fx,fy,ci,c,r,row,col,lx,ly,idx;
    reg overlay,dark_ink,text_select;reg [1:0] text_lane;
    always @*begin
        overlay=x<704&&(page==0||page>=3);dark_ink=0;color=24'h09111d;letter=32;fx=0;fy=0;ci=0;
        text=0;row=0;col=0;lx=0;ly=0;idx=0;key_color=0;text_select=0;text_lane=0;text_address=0;
        if(page==0)begin
            for(c=0;c<6;c=c+1)if(x>=32+(c%3)*224&&x<232+(c%3)*224&&y>=96+(c/3)*168&&y<240+(c/3)*168)begin
                case(c)0:color=24'h153c53;1:color=24'h223655;2:color=24'h493040;3:color=24'h4b4325;4:color=24'h34445d;default:color=24'h285643;endcase
                // 六个简单图标不需要帧缓存或图像ROM。
                if(x>=96+(c%3)*224&&x<168+(c%3)*224&&y>=128+(c/3)*168&&y<176+(c/3)*168)begin
                    if(c==0||c==4)begin if(x[3:0]<8&&y>=144+(c/3)*168-(x[5:4]*8))color=24'h32d39a;end
                    else if(c==1)begin if(x[3:0]<12)color=24'hd9e2ef;end
                    else if(c==2)color=24'hd96464;
                    else if(c==3)color=24'heab15b;
                    else if((x[4]^y[4])==0)color=24'h51e5a6;
                end
                if(x>=72+(c%3)*224&&x<216+(c%3)*224&&y>=204+(c/3)*168&&y<218+(c/3)*168)begin
                    letter=string_char(app_name(c),div12(x-(72+(c%3)*224)));fx=mod12(x-(72+(c%3)*224))>>1;fy=glyph_half(y,204+(c/3)*168);
                end
            end
        end
        if(page==6)begin
            for(c=0;c<5;c=c+1)if(x>=48&&x<656&&y>=96+c*60&&y<148+c*60)begin
                color=(selected_timbre==c)?24'h24654f:24'h193149;
                if((x<52||x>=652||y<98+c*60||y>=146+c*60)&&selected_timbre==c)color=24'h51e5a6;
                if(x>=104&&x<296&&y>=114+c*60&&y<128+c*60)begin
                    letter=string_char(timbre_name(c),div12(x-10'd104));fx=mod12(x-10'd104)>>1;fy=glyph_half(y,114+c*60);
                end
                if(selected_timbre==c&&x>=548&&x<620&&y>=114+c*60&&y<128+c*60)begin
                    letter=string_char("ACTIVE          ",div12(x-10'd548));fx=mod12(x-10'd548)>>1;fy=glyph_half(y,114+c*60);
                end
            end
            if(x>=48&&x<624&&y>=412&&y<426)begin
                letter=string_char("RELEASE AND PLAY",div12(x-10'd48));fx=mod12(x-10'd48)>>1;fy=glyph_half(y,412);
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
        if(page==7)begin
            for(r=0;r<6;r=r+1)if(!game_running&&x>=16&&x<672&&y>=80+r*28&&y<104+r*28)begin
                color=r<file_count?24'h153044:24'h101d2b;
                if(x>=32&&x<416&&y>=85+r*28&&y<99+r*28)begin
                    ci=div12(x-10'd32);text_select=1;text_address=r*8+(ci>>2);text_lane=ci[1:0];fx=mod12(x-10'd32)>>1;fy=glyph_half(y,85+r*28);
                end
            end
            if(!game_running&&y>=232&&y<258)for(c=0;c<2;c=c+1)if(x>=16+c*224&&x<208+c*224)begin
                color=24'h265faa;
                if(x>=32+c*224&&x<200+c*224&&y>=238&&y<252)begin
                    letter=string_char(c==0?"PREV SONGS      ":"NEXT SONGS      ",div12(x-(32+c*224)));fx=mod12(x-(32+c*224))>>1;fy=glyph_half(y,238);
                end
            end
            if(game_running&&x>=32&&x<416&&y>=96&&y<110)begin ci=div12(x-10'd32);text_select=1;text_address=56+(ci>>2);text_lane=ci[1:0];fx=mod12(x-10'd32)>>1;fy=glyph_half(y,96);end
            if(game_running&&y>=144&&y<158&&x>=32&&x<416)begin
                text=game[127:112]!=0?"GET READY       ":game_waiting?"WAITING DATA    ":game[129]?"PAUSED          ":game_practice?"PRACTICE        ":"CHALLENGE       ";
                letter=string_char(text,div12(x-10'd32));fx=mod12(x-10'd32)>>1;fy=glyph_half(y,144);
            end
            if((game_running||game_complete)&&y>=184&&y<198&&x>=32&&x<416)begin
                ci=div12(x-10'd32);fx=mod12(x-10'd32)>>1;fy=glyph_half(y,184);
                if(ci<6)letter=string_char("SCORE           ",ci);
                else if(ci<12)letter="0"+((game[55:32]>>((11-ci)*4))&4'hf);
            end
            for(c=0;c<7;c=c+1)for(r=0;r<4;r=r+1)if(x>=16+c*96&&x<106+c*96&&y>=264+r*30&&y<290+r*30)begin
                idx=r*7+c;color=keys[idx]?24'h32d39a:guide[idx]?24'h4794ed:24'hd9e2ef;dark_ink=1;lx=x-(16+c*96);ly=y-(264+r*30);
                if(lx>=32&&lx<56&&ly>=6&&ly<20)begin
                    fx=lx<44?glyph_half(lx,32):glyph_half(lx,44);fy=glyph_half(ly,6);
                    if(lx<44)case(c)0:letter="C";1:letter="D";2:letter="E";3:letter="F";4:letter="G";5:letter="A";default:letter="B";endcase
                    else letter="3"+r;
                end
            end
            if(y>=400&&y<432)for(c=0;c<3;c=c+1)if(x>=16+c*224&&x<208+c*224)begin
                color=24'h265faa;if(x>=32+c*224&&x<200+c*224&&y>=410&&y<424)begin
                    text=c==0?(game_practice?"PRACTICE        ":"CHALLENGE       "):c==1?"PAUSE/GO        ":"STOP            ";
                    letter=string_char(text,div12(x-(32+c*224)));fx=mod12(x-(32+c*224))>>1;fy=glyph_half(y,410);
                end
            end
            if(x>=16&&x<400&&y>=56&&y<70)begin letter=string_char(game_complete?"SONG COMPLETE   ":"SELECT A SONG   ",div12(x-10'd16));fx=mod12(x-10'd16)>>1;fy=glyph_half(y,56);end
        end
        if(page==4&&x>=480&&x<672&&y>=72&&y<94)begin
            color=usb_exported?24'ha7364d:24'h286d52;
            if(x>=496&&x<664&&y>=76&&y<90)begin letter=string_char(usb_exported?"EJECT DISK      ":"USB DISK        ",div12(x-10'd496));fx=mod12(x-10'd496)>>1;fy=glyph_half(y,76);end
        end
        if(page==4&&usb_exported&&y>=96&&y<376)begin
            color=24'h152c41;letter=32;text_select=0;
            if(x>=80&&x<464&&y>=184&&y<198)begin letter=string_char("PHONE OWNS CARD ",div12(x-10'd80));fx=mod12(x-10'd80)>>1;fy=glyph_half(y,184);end
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
            text=page==0?"PIANO HOME D12  ":page==3?"RECORDER        ":page==4?"FILE MANAGER    ":page==6?"TIMBRE D12      ":page==7?"PIANO GAME D12  ":"AUDIO PLAYER    ";
            letter=string_char(text,div12(x-10'd16));fx=mod12(x-10'd16)>>1;fy=glyph_half(y,16);
        end
        if(x>=16&&x<400&&y>=446&&y<460)begin
            letter=string_char(message_text(msg),div12(x-10'd16));fx=mod12(x-10'd16)>>1;fy=glyph_half(y,446);
        end
        // 五种音色的名称也显示在其他演奏页面；文件播放器保持自己的音源。
        if(page!=4&&page!=5&&x>=432&&x<624&&y>=16&&y<30)begin
            overlay=1;letter=string_char(timbre_name(selected_timbre),div12(x-10'd432));fx=mod12(x-10'd432)>>1;fy=glyph_half(y,16);
        end
        if(page!=4&&page!=5&&x>=480&&x<672&&y>=56&&y<70)begin
            overlay=1;dark_ink=0;
            text=(selected_timbre==3||selected_timbre==4)?(effects[selected_timbre]?"VIB ON          ":"VIB OFF         "):(effects[selected_timbre]?"DARK            ":"BRIGHT          ");
            letter=string_char(text,div12(x-10'd480));fx=mod12(x-10'd480)>>1;fy=glyph_half(y,56);
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
    reg [23:0] background_d,overlay_rgb;reg [143:0] letter_d;reg [2:0] fx_d,fy_d;
    wire [5:0] index_d=6'd34-fy_d*6'd5-fx_d;
    wire [7:0] decoded_letter=letter_d[143]?text_byte(letter_d[142:15],letter_d[14:8]):letter_d[7:0];
    reg valid_d,ink_d,de_d,en_d,en_q;
    reg text_select_d;reg [1:0] text_lane_d;
    wire [7:0] ram_letter=text_data[text_lane_d*8+:8];
    wire [34:0] bits=glyph(text_select_d?upper_char(ram_letter):decoded_letter);
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin background_d<=0;overlay_rgb<=0;letter_d<=32;fx_d<=0;fy_d<=0;valid_d<=0;ink_d<=0;de_d<=0;en_d<=0;en_q<=0;text_select_d<=0;text_lane_d<=0;end
        else begin
            background_d<=color;letter_d<=letter;text_select_d<=text_select;text_lane_d<=text_lane;fx_d<=fx[2:0];fy_d<=fy[2:0];
            valid_d<=fx>=0&&fx<5&&fy>=0&&fy<7;ink_d<=dark_ink;de_d<=de;en_d<=overlay;en_q<=en_d;
            overlay_rgb<=!de_d?24'd0:((valid_d&&bits[index_d])?(ink_d?24'h09111d:24'he6edf5):background_d);
        end
    end
    assign rgb=en_q?overlay_rgb:base_rgb;
endmodule
