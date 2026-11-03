`timescale 1ns/1ps
module spectrum_cdc #(parameter integer WIDTH=268) (
    input wire src_clk, src_rst_n, input wire [WIDTH-1:0] src_data,
    input wire dst_clk, dst_rst_n, dst_frame,
    output reg [WIDTH-1:0] dst_data, output reg dst_valid
);
    reg [WIDTH-1:0] held_data;
    reg request, acknowledge;
    (* ASYNC_REG="TRUE", syn_keep=1 *) reg ack_meta, ack_seen, req_meta, req_seen;
    always @(posedge src_clk or negedge src_rst_n) begin
        if(!src_rst_n) begin request<=0; held_data<=0; ack_meta<=0; ack_seen<=0; end
        else begin
            ack_meta<=acknowledge; ack_seen<=ack_meta;
            if(ack_seen==request) begin
                held_data<=src_data; request<=~request; // 保持总线不变，直到显示域确认接收
            end
        end
    end
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if(!dst_rst_n) begin req_meta<=0; req_seen<=0; acknowledge<=0; dst_data<=0; dst_valid<=0; end
        else begin
            req_meta<=request; req_seen<=req_meta; dst_valid<=0;
            if(dst_frame && req_seen!=acknowledge) begin
                dst_data<=held_data; dst_valid<=1; acknowledge<=req_seen; // 只在消隐期原子换帧
            end
        end
    end
endmodule

module spectrum_timing (
    input wire clk, rst_n,
    output reg [9:0] x, y,
    output wire hs, vs, de, frame_tick
);
    // 800x480 自定义 60 Hz：30 MHz，1000x500 总像素；实屏锁定仍需测试。
    // 接近厂家 CVT 模式，水平后肩增加8像素，以整数 PLL 保证精确帧率。
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin x<=0; y<=0; end
        else if(x==999) begin x<=0; if(y==499) y<=0; else y<=y+1'b1; end
        else x<=x+1'b1;
    end
    assign hs=!(x>=824 && x<896);                  // 负极性行同步，前肩24、同步72、后肩104
    assign vs=(y>=483 && y<490);                  // CVT 15:9 正极性场同步，前肩3、同步7、后肩10
    assign de=(x<800 && y<480);
    assign frame_tick=(x==0 && y==480);           // 每帧进入垂直消隐时更新状态和动画
endmodule

module spectrum_renderer #(parameter integer KEY_COUNT=7) (
    input wire clk, rst_n, frame_tick, snapshot_valid,
    input wire [KEY_COUNT+260:0] snapshot,
    input wire [9:0] x,y, input wire hs,vs,de,
    output reg hs_out,vs_out,de_out,
    output reg [23:0] rgb
);
    reg [255:0] target, shown, peaks;
    reg [KEY_COUNT-1:0] keys;
    reg signed [3:0] transpose;
    reg dark;
    reg [2:0] peak_timer;
    integer k;
    reg [9:0] smooth_value;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin target<=0; shown<=0; peaks<=0; keys<=0; transpose<=0; dark<=0; peak_timer<=0; end
        else begin
            if(snapshot_valid) begin
                target<=snapshot[255:0]; keys<=snapshot[256 +: KEY_COUNT]; // 一次换入完整的7键或28键状态
                transpose<=snapshot[256+KEY_COUNT +: 4]; dark<=snapshot[260+KEY_COUNT];
            end
            if(frame_tick) begin
                if(peak_timer==5) peak_timer<=0; else peak_timer<=peak_timer+1'b1;
                for(k=0;k<32;k=k+1) begin
                    // 固定按视频帧更新；约 60 Hz，攻速快、回落平滑，静音最终归零。
                    if(target[k*8 +: 8]>shown[k*8 +: 8])
                        smooth_value=({2'b0,shown[k*8 +: 8]}+{2'b0,target[k*8 +: 8]}+1)>>1;
                    else smooth_value=(({2'b0,shown[k*8 +: 8]}<<1)+{2'b0,shown[k*8 +: 8]}+{2'b0,target[k*8 +: 8]})>>2;
                    shown[k*8 +: 8]<=smooth_value[7:0];
                    if(smooth_value>peaks[k*8 +: 8]) peaks[k*8 +: 8]<=smooth_value[7:0];
                    else if(peak_timer==5) begin
                        if(peaks[k*8 +: 8]>3) peaks[k*8 +: 8]<=peaks[k*8 +: 8]-3;
                        else peaks[k*8 +: 8]<=0;   // 峰值约每100 ms下降三档
                    end
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
                "K":glyph=35'b10001_10010_10100_11000_10100_10010_10001;
                "M":glyph=35'b10001_11011_10101_10101_10001_10001_10001;
                "N":glyph=35'b10001_11001_10101_10011_10001_10001_10001;
                "O":glyph=35'b01110_10001_10001_10001_10001_10001_01110;
                "P":glyph=35'b11110_10001_10001_11110_10000_10000_10000;
                "R":glyph=35'b11110_10001_10001_11110_10100_10010_10001;
                "S":glyph=35'b01111_10000_10000_01110_00001_00001_11110;
                "T":glyph=35'b11111_00100_00100_00100_00100_00100_00100;
                "U":glyph=35'b10001_10001_10001_10001_10001_10001_01110;
                "V":glyph=35'b10001_10001_10001_10001_10001_01010_00100;
                "Y":glyph=35'b10001_10001_01010_00100_00100_00100_00100;
                "+":glyph=35'b00000_00100_00100_11111_00100_00100_00000;
                "-":glyph=35'b00000_00000_00000_11111_00000_00000_00000;
                default:glyph=0;
            endcase
        end
    endfunction
    function [7:0] title_char;
        input [5:0] index;
        reg [8*32-1:0] title;
        begin
            if(KEY_COUNT==28) title={"28 KEYS 32 BANDS 48K",96'h202020202020202020202020}; // 20字节标题+12空格，精确32字节
            else title={"PIANO SPECTRUM 32 BANDS 48K",40'h2020202020};
            title_char=title[(31-index)*8 +: 8];
        end
    endfunction
    reg [23:0] color;
    reg [7:0] letter;
    reg [34:0] bits_font;
    integer column, local_x, height, peak_height, key_index, font_x, font_y, char_index, abs_transpose;
    always @* begin
        color=24'h09111d; letter=32; bits_font=0;
        column=0; local_x=0; height=0; peak_height=0; key_index=0;
        font_x=0; font_y=0; char_index=0;
        abs_transpose=transpose[3] ? -$signed(transpose) : transpose;
        if(y>=52 && y<374 && x>=16 && x<784) begin
            column=(x-16)/24; local_x=(x-16)%24;
            height=((shown[column*8 +: 8]<<2)+shown[column*8 +: 8])>>2;
            peak_height=((peaks[column*8 +: 8]<<2)+peaks[column*8 +: 8])>>2;
            if(y==132 || y==212 || y==292 || y==372) color=24'h1b2b3d;
            if(local_x<18 && height!=0 && y>=372-height && y<372) begin
                color[23:16]=((372-y)*3)>>2; color[15:8]=255-(((372-y)*3)>>2); color[7:0]=24;
            end
            if(local_x<18 && peak_height!=0 && y>=372-peak_height && y<374-peak_height) color=24'hffffff;
        end
        if(y>=400) color=24'h142339;
        if(KEY_COUNT==7 && x>=16 && x<436 && y>=416 && y<464) begin
            key_index=(x-16)/60;
            if(((x-16)%60)<54) color=keys[key_index] ? 24'h32d39a : 24'hd9e2ef;
            if(((x-16)%60)>=22 && ((x-16)%60)<32 && y>=434 && y<448) begin
                case(key_index) 0:letter="C";1:letter="D";2:letter="E";3:letter="F";4:letter="G";5:letter="A";6:letter="B";default:letter=32;endcase
                font_x=(((x-16)%60)-22)/2; font_y=(y-434)/2;
            end
        end
        if(KEY_COUNT==28 && x>=16 && x<436 && y>=400 && y<480) begin
            key_index=((y-400)/20)*7+(x-16)/60; // 从上到下C3、C4、C5、C6四组白键
            if(((x-16)%60)<54 && ((y-400)%20)<18)
                color=keys[key_index] ? 24'h32d39a : 24'hd9e2ef;
            if(((y-400)%20)>=6 && ((y-400)%20)<13) begin
                if(((x-16)%60)>=20 && ((x-16)%60)<25) begin
                    case((x-16)/60) 0:letter="C";1:letter="D";2:letter="E";3:letter="F";4:letter="G";5:letter="A";6:letter="B";default:letter=32;endcase
                    font_x=((x-16)%60)-20; font_y=((y-400)%20)-6;
                end else if(((x-16)%60)>=27 && ((x-16)%60)<32) begin
                    letter="3"+(y-400)/20; font_x=((x-16)%60)-27; font_y=((y-400)%20)-6;
                end
            end
        end
        if(x>=16 && x<784 && y>=16 && y<30) begin
            char_index=(x-16)/12; font_x=((x-16)%12)/2; font_y=(y-16)/2;
            if(char_index<32) letter=title_char(char_index);
        end
        if(x>=472 && x<784 && y>=418 && y<432) begin
            char_index=(x-472)/12; font_x=((x-472)%12)/2; font_y=(y-418)/2;
            case(char_index)
                0:letter="T";1:letter="R";2:letter="A";3:letter="N";4:letter="S";
                6:letter=transpose[3] ? "-" : "+";7:letter="0"+abs_transpose;
                default:letter=32;
            endcase
        end
        if(x>=472 && x<784 && y>=446 && y<460) begin
            char_index=(x-472)/12; font_x=((x-472)%12)/2; font_y=(y-446)/2;
            if(dark) case(char_index) 0:letter="D";1:letter="A";2:letter="R";3:letter="K";default:letter=32;endcase
            else case(char_index) 0:letter="B";1:letter="R";2:letter="I";3:letter="G";4:letter="H";5:letter="T";default:letter=32;endcase
        end
        bits_font=glyph(letter);
        if(font_x<5 && font_y<7 && bits_font[34-font_y*5-font_x])
            color=(x<436 && ((KEY_COUNT==28 && y>=400) || (KEY_COUNT==7 && y>=434))) ? 24'h09111d : 24'he6edf5;
        if(!de) color=0;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin rgb<=0; hs_out<=1; vs_out<=0; de_out<=0; end
        else begin rgb<=color; hs_out<=hs; vs_out<=vs; de_out<=de; end // 像素与同步同延迟一个周期
    end
endmodule
