`timescale 1ns/1ps
// 八页/六应用UI：录音与文件命令发往CPU，触摸键/双柱仍在50MHz硬件中即时处理。
module media_ui28 #(parameter integer ENABLE_EXTRA_APPS=0)(input wire clk,rst_n,frame_valid,connected,input wire [4:0] active,
    input wire [39:0] ids,input wire [49:0] xs,ys,input wire game_running,usb_exported,input wire nav_valid,input wire [3:0] nav_page,
    output reg [27:0] touch_keys,output reg [6:0] volume_percent,output reg [3:0] page,
    output reg transpose_set_valid,output reg signed [3:0] transpose_set,
    output reg command_valid,output reg [31:0] command,
    output reg [2:0] timbre_selected,
    output reg validation_run,output reg [5:0] validation_count,
    output reg [2:0] fx_enabled,output reg [20:0] fx_levels); // 0钢琴、1电钢琴、2风琴、3吉他、4弦乐
    (* syn_preserve=1 *)reg [19:0] decode_pages; // 五指各自局部译码，始终等于五份page。
    localparam BLOCK=0,KEY=1,VOLUME=2,ACTION=3,TONE=4,SEEK=5;
    reg [4:0] old_active;reg [39:0] old_id;reg [19:0] old_role;
    reg volume_owned,tone_owned,seek_owned;reg [7:0] volume_id,tone_id,seek_id;reg [9:0] seek_value;
    function [4:0] key_at(input [3:0] p,input [9:0] px,py);
        reg [2:0] column;reg [4:0] row_base;reg column_valid,row_valid;integer c,r;
        begin
            column=0;row_base=0;column_valid=0;row_valid=0;
            for(c=0;c<7;c=c+1)if(px>=16+c*96&&px<106+c*96)begin column=c;column_valid=1;end
            // 行偏移直接选择0/7/14/21，避免32位带符号行号乘7后再缩成5位。
            for(r=0;r<4;r=r+1)begin
                if((p==1&&py>=304+r*28&&py<328+r*28)||
                   (p==2&&py>=96+r*80&&py<170+r*80)||
                   (p==3&&py>=96+r*60&&py<150+r*60)||
                   (p==7&&py>=264+r*30&&py<290+r*30))begin row_base=r*7;row_valid=1;end
            end
            key_at=column_valid&&row_valid?row_base+{2'd0,column}:5'd31;
        end
    endfunction
    function [6:0] volume_at(input [9:0] py);
        begin case(py)
            10'd0, 10'd1, 10'd2, 10'd3, 10'd4, 10'd5, 10'd6, 10'd7, 10'd8, 10'd9, 10'd10, 10'd11, 10'd12, 10'd13, 10'd14, 10'd15, 10'd16, 10'd17, 10'd18, 10'd19, 10'd20, 10'd21, 10'd22, 10'd23, 10'd24, 10'd25, 10'd26, 10'd27, 10'd28, 10'd29, 10'd30, 10'd31, 10'd32, 10'd33, 10'd34, 10'd35, 10'd36, 10'd37, 10'd38, 10'd39, 10'd40, 10'd41, 10'd42, 10'd43, 10'd44, 10'd45, 10'd46, 10'd47, 10'd48, 10'd49, 10'd50, 10'd51, 10'd52, 10'd53, 10'd54, 10'd55, 10'd56, 10'd57, 10'd58, 10'd59, 10'd60, 10'd61, 10'd62, 10'd63, 10'd64, 10'd65: volume_at=7'd100;
            10'd66, 10'd67, 10'd68, 10'd69: volume_at=7'd99;
            10'd70, 10'd71, 10'd72: volume_at=7'd98;
            10'd73, 10'd74, 10'd75: volume_at=7'd97;
            10'd76, 10'd77, 10'd78, 10'd79: volume_at=7'd96;
            10'd80, 10'd81, 10'd82: volume_at=7'd95;
            10'd83, 10'd84, 10'd85: volume_at=7'd94;
            10'd86, 10'd87, 10'd88, 10'd89: volume_at=7'd93;
            10'd90, 10'd91, 10'd92: volume_at=7'd92;
            10'd93, 10'd94, 10'd95: volume_at=7'd91;
            10'd96, 10'd97, 10'd98, 10'd99: volume_at=7'd90;
            10'd100, 10'd101, 10'd102: volume_at=7'd89;
            10'd103, 10'd104, 10'd105, 10'd106: volume_at=7'd88;
            10'd107, 10'd108, 10'd109: volume_at=7'd87;
            10'd110, 10'd111, 10'd112: volume_at=7'd86;
            10'd113, 10'd114, 10'd115, 10'd116: volume_at=7'd85;
            10'd117, 10'd118, 10'd119: volume_at=7'd84;
            10'd120, 10'd121, 10'd122: volume_at=7'd83;
            10'd123, 10'd124, 10'd125, 10'd126: volume_at=7'd82;
            10'd127, 10'd128, 10'd129: volume_at=7'd81;
            10'd130, 10'd131, 10'd132: volume_at=7'd80;
            10'd133, 10'd134, 10'd135, 10'd136: volume_at=7'd79;
            10'd137, 10'd138, 10'd139: volume_at=7'd78;
            10'd140, 10'd141, 10'd142: volume_at=7'd77;
            10'd143, 10'd144, 10'd145, 10'd146: volume_at=7'd76;
            10'd147, 10'd148, 10'd149: volume_at=7'd75;
            10'd150, 10'd151, 10'd152, 10'd153: volume_at=7'd74;
            10'd154, 10'd155, 10'd156: volume_at=7'd73;
            10'd157, 10'd158, 10'd159: volume_at=7'd72;
            10'd160, 10'd161, 10'd162, 10'd163: volume_at=7'd71;
            10'd164, 10'd165, 10'd166: volume_at=7'd70;
            10'd167, 10'd168, 10'd169: volume_at=7'd69;
            10'd170, 10'd171, 10'd172, 10'd173: volume_at=7'd68;
            10'd174, 10'd175, 10'd176: volume_at=7'd67;
            10'd177, 10'd178, 10'd179: volume_at=7'd66;
            10'd180, 10'd181, 10'd182, 10'd183: volume_at=7'd65;
            10'd184, 10'd185, 10'd186: volume_at=7'd64;
            10'd187, 10'd188, 10'd189, 10'd190: volume_at=7'd63;
            10'd191, 10'd192, 10'd193: volume_at=7'd62;
            10'd194, 10'd195, 10'd196: volume_at=7'd61;
            10'd197, 10'd198, 10'd199, 10'd200: volume_at=7'd60;
            10'd201, 10'd202, 10'd203: volume_at=7'd59;
            10'd204, 10'd205, 10'd206: volume_at=7'd58;
            10'd207, 10'd208, 10'd209, 10'd210: volume_at=7'd57;
            10'd211, 10'd212, 10'd213: volume_at=7'd56;
            10'd214, 10'd215, 10'd216: volume_at=7'd55;
            10'd217, 10'd218, 10'd219, 10'd220: volume_at=7'd54;
            10'd221, 10'd222, 10'd223: volume_at=7'd53;
            10'd224, 10'd225, 10'd226: volume_at=7'd52;
            10'd227, 10'd228, 10'd229, 10'd230: volume_at=7'd51;
            10'd231, 10'd232, 10'd233: volume_at=7'd50;
            10'd234, 10'd235, 10'd236, 10'd237: volume_at=7'd49;
            10'd238, 10'd239, 10'd240: volume_at=7'd48;
            10'd241, 10'd242, 10'd243: volume_at=7'd47;
            10'd244, 10'd245, 10'd246, 10'd247: volume_at=7'd46;
            10'd248, 10'd249, 10'd250: volume_at=7'd45;
            10'd251, 10'd252, 10'd253: volume_at=7'd44;
            10'd254, 10'd255, 10'd256, 10'd257: volume_at=7'd43;
            10'd258, 10'd259, 10'd260: volume_at=7'd42;
            10'd261, 10'd262, 10'd263: volume_at=7'd41;
            10'd264, 10'd265, 10'd266, 10'd267: volume_at=7'd40;
            10'd268, 10'd269, 10'd270: volume_at=7'd39;
            10'd271, 10'd272, 10'd273, 10'd274: volume_at=7'd38;
            10'd275, 10'd276, 10'd277: volume_at=7'd37;
            10'd278, 10'd279, 10'd280: volume_at=7'd36;
            10'd281, 10'd282, 10'd283, 10'd284: volume_at=7'd35;
            10'd285, 10'd286, 10'd287: volume_at=7'd34;
            10'd288, 10'd289, 10'd290: volume_at=7'd33;
            10'd291, 10'd292, 10'd293, 10'd294: volume_at=7'd32;
            10'd295, 10'd296, 10'd297: volume_at=7'd31;
            10'd298, 10'd299, 10'd300: volume_at=7'd30;
            10'd301, 10'd302, 10'd303, 10'd304: volume_at=7'd29;
            10'd305, 10'd306, 10'd307: volume_at=7'd28;
            10'd308, 10'd309, 10'd310: volume_at=7'd27;
            10'd311, 10'd312, 10'd313, 10'd314: volume_at=7'd26;
            10'd315, 10'd316, 10'd317: volume_at=7'd25;
            10'd318, 10'd319, 10'd320, 10'd321: volume_at=7'd24;
            10'd322, 10'd323, 10'd324: volume_at=7'd23;
            10'd325, 10'd326, 10'd327: volume_at=7'd22;
            10'd328, 10'd329, 10'd330, 10'd331: volume_at=7'd21;
            10'd332, 10'd333, 10'd334: volume_at=7'd20;
            10'd335, 10'd336, 10'd337: volume_at=7'd19;
            10'd338, 10'd339, 10'd340, 10'd341: volume_at=7'd18;
            10'd342, 10'd343, 10'd344: volume_at=7'd17;
            10'd345, 10'd346, 10'd347: volume_at=7'd16;
            10'd348, 10'd349, 10'd350, 10'd351: volume_at=7'd15;
            10'd352, 10'd353, 10'd354: volume_at=7'd14;
            10'd355, 10'd356, 10'd357, 10'd358: volume_at=7'd13;
            10'd359, 10'd360, 10'd361: volume_at=7'd12;
            10'd362, 10'd363, 10'd364: volume_at=7'd11;
            10'd365, 10'd366, 10'd367, 10'd368: volume_at=7'd10;
            10'd369, 10'd370, 10'd371: volume_at=7'd9;
            10'd372, 10'd373, 10'd374: volume_at=7'd8;
            10'd375, 10'd376, 10'd377, 10'd378: volume_at=7'd7;
            10'd379, 10'd380, 10'd381: volume_at=7'd6;
            10'd382, 10'd383, 10'd384: volume_at=7'd5;
            10'd385, 10'd386, 10'd387, 10'd388: volume_at=7'd4;
            10'd389, 10'd390, 10'd391: volume_at=7'd3;
            10'd392, 10'd393, 10'd394: volume_at=7'd2;
            10'd395, 10'd396, 10'd397, 10'd398: volume_at=7'd1;
            default: volume_at=0;
        endcase end
    endfunction
    function signed [3:0] tone_at(input [9:0] py);
        begin
            if(py<=80) tone_at=4'sd5;
            else if(py<=114) tone_at=4'sd4;
            else if(py<=148) tone_at=4'sd3;
            else if(py<=181) tone_at=4'sd2;
            else if(py<=215) tone_at=4'sd1;
            else if(py<=248) tone_at=4'sd0;
            else if(py<=282) tone_at=-4'sd1;
            else if(py<=316) tone_at=-4'sd2;
            else if(py<=349) tone_at=-4'sd3;
            else if(py<=383) tone_at=-4'sd4;
            else tone_at=-4'sd5;
        end
    endfunction
    function [9:0] seek_at(input [9:0] px);
        begin if(px<=48)seek_at=0;else if(px>=656)seek_at=1000;else case((px-10'd48)>>4)
            6'd0:seek_at=10'd0;
            6'd1:seek_at=10'd26;
            6'd2:seek_at=10'd53;
            6'd3:seek_at=10'd79;
            6'd4:seek_at=10'd105;
            6'd5:seek_at=10'd132;
            6'd6:seek_at=10'd158;
            6'd7:seek_at=10'd184;
            6'd8:seek_at=10'd211;
            6'd9:seek_at=10'd237;
            6'd10:seek_at=10'd263;
            6'd11:seek_at=10'd289;
            6'd12:seek_at=10'd316;
            6'd13:seek_at=10'd342;
            6'd14:seek_at=10'd368;
            6'd15:seek_at=10'd395;
            6'd16:seek_at=10'd421;
            6'd17:seek_at=10'd447;
            6'd18:seek_at=10'd474;
            6'd19:seek_at=10'd500;
            6'd20:seek_at=10'd526;
            6'd21:seek_at=10'd553;
            6'd22:seek_at=10'd579;
            6'd23:seek_at=10'd605;
            6'd24:seek_at=10'd632;
            6'd25:seek_at=10'd658;
            6'd26:seek_at=10'd684;
            6'd27:seek_at=10'd711;
            6'd28:seek_at=10'd737;
            6'd29:seek_at=10'd763;
            6'd30:seek_at=10'd789;
            6'd31:seek_at=10'd816;
            6'd32:seek_at=10'd842;
            6'd33:seek_at=10'd868;
            6'd34:seek_at=10'd895;
            6'd35:seek_at=10'd921;
            6'd36:seek_at=10'd947;
            6'd37:seek_at=10'd974;
            default:seek_at=1000;
        endcase end
    endfunction

    // 第一级预译码每个触点。第二级只合并五个归属/事件，切断page到五重优先链的长路径。
    reg frame_pending;reg [4:0] p_active,p_matched,p_nav,p_nav_force;
    reg [4:0] p_volume_match,p_tone_match,p_seek_match;reg [24:0] p_equal;
    reg p_volume_present,p_tone_present,p_seek_present;
    reg [39:0] p_ids;reg [49:0] p_xs,p_ys;
    reg [19:0] p_role,p_old_role,p_nav_page;
    reg [24:0] p_key;reg [34:0] p_volume;reg signed [19:0] p_tone;
    reg [49:0] p_seek;reg [159:0] p_command;
    integer f,g,k,px,py;reg v_present,t_present,s_present;reg [3:0] candidate;reg matched_now;reg [3:0] previous_role;
    // 数据流水寄存器不做大扇出异步复位；只有valid异步清零，未提交的数据永远不可见。
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)frame_pending<=0;
        else frame_pending<=frame_valid&&connected&&!nav_valid;
    end
    always @(posedge clk)begin
        begin
            if(frame_valid&&connected&&!nav_valid)begin
                p_active<=active;p_ids<=ids;p_xs<=xs;p_ys<=ys;
                v_present=0;t_present=0;s_present=0;
                for(f=0;f<5;f=f+1)begin
                    p_volume_match[f]<=ids[f*8+:8]==volume_id;p_tone_match[f]<=ids[f*8+:8]==tone_id;p_seek_match[f]<=ids[f*8+:8]==seek_id;
                    if(active[f]&&ids[f*8+:8]==volume_id)v_present=1;
                    if(active[f]&&ids[f*8+:8]==tone_id)t_present=1;
                    if(active[f]&&ids[f*8+:8]==seek_id)s_present=1;
                    for(g=0;g<5;g=g+1)p_equal[f*5+g]<=ids[f*8+:8]==ids[g*8+:8];
                end
                p_volume_present<=v_present;p_tone_present<=t_present;p_seek_present<=s_present;
                for(f=0;f<5;f=f+1)begin
                    px=xs[f*10+:10];py=ys[f*10+:10];matched_now=0;previous_role=BLOCK;
                    for(g=0;g<5;g=g+1)if(old_active[g]&&old_id[(g)*8+:8]==ids[f*8+:8])begin matched_now=1;previous_role=old_role[(g)*4+:4];end
                    p_matched[f]<=matched_now;p_old_role[(f)*4+:4]<=previous_role;p_nav[f]<=0;p_nav_force[f]<=0;p_nav_page[(f)*4+:4]<=0;p_command[(f)*32+:32]<=0;
                    p_key[(f)*5+:5]<=key_at(decode_pages[f*4+:4],xs[f*10+:10],ys[f*10+:10]);p_volume[(f)*7+:7]<=volume_at(ys[f*10+:10]);p_tone[(f)*4+:4]<=tone_at(ys[f*10+:10]);p_seek[(f)*10+:10]<=seek_at(xs[f*10+:10]);
                    candidate=BLOCK;
                    if(px>=704&&px<750&&py>=48&&py<416)candidate=VOLUME;
                    else if(decode_pages[f*4+:4]!=5&&px>=754&&px<800&&py>=48&&py<416)candidate=TONE;
                    else if(px>=704&&px<792&&py>=432&&py<476)begin candidate=ACTION;p_nav[f]<=1;p_nav_page[(f)*4+:4]<=0;end
                    else if(decode_pages[f*4+:4]==8&&ENABLE_EXTRA_APPS)begin
                        candidate=ACTION;
                        if(py>=352&&py<408&&px>=32&&px<224)p_command[f*32+:32]<=32'h20000000;
                        for(k=0;k<6;k=k+1)if(py>=288&&py<336&&px>=32+k*108&&px<128+k*108)
                            case(k)0:p_command[f*32+:32]<=32'h20000001;1:p_command[f*32+:32]<=32'h20000004;2:p_command[f*32+:32]<=32'h20000008;
                            3:p_command[f*32+:32]<=32'h20000010;4:p_command[f*32+:32]<=32'h2000001c;5:p_command[f*32+:32]<=32'h20000020;endcase
                    end else if(decode_pages[f*4+:4]==9&&ENABLE_EXTRA_APPS)begin
                        candidate=BLOCK;
                        for(k=0;k<3;k=k+1)begin
                            if(py>=96+k*104&&py<160+k*104&&px>=32&&px<176)begin candidate=ACTION;p_command[f*32+:32]<=32'h21000000|k;end
                            if(py>=112+k*104&&py<152+k*104&&px>=192&&px<656)begin
                                candidate=6+k;p_seek[f*10+:10]<=(px<=208)?0:(px>=608)?100:(px-208)>>2;
                            end
                        end
                    end else if(decode_pages[f*4+:4]==0&&ENABLE_EXTRA_APPS)begin
                        candidate=ACTION;
                        for(k=0;k<8;k=k+1)if(px>=16+(k%4)*172&&px<172+(k%4)*172&&py>=96+(k/4)*168&&py<240+(k/4)*168)begin
                            p_nav[f]<=1;
                            case(k)0:p_nav_page[f*4+:4]<=1;1:p_nav_page[f*4+:4]<=2;2:p_nav_page[f*4+:4]<=3;3:p_nav_page[f*4+:4]<=4;
                                4:p_nav_page[f*4+:4]<=6;5:p_nav_page[f*4+:4]<=7;6:p_nav_page[f*4+:4]<=8;7:p_nav_page[f*4+:4]<=9;endcase
                        end
                    end else if(decode_pages[f*4+:4]==0&&!ENABLE_EXTRA_APPS)begin
                        candidate=ACTION;
                        // Home统一2排3列，点击区与渲染坐标共用同一组边界。
                        for(k=0;k<6;k=k+1)if(px>=32+(k%3)*224&&px<232+(k%3)*224&&py>=96+(k/3)*168&&py<240+(k/3)*168)begin
                            p_nav[f]<=1;
                            case(k)0:p_nav_page[(f)*4+:4]<=1;1:p_nav_page[(f)*4+:4]<=2;2:p_nav_page[(f)*4+:4]<=3;
                                3:p_nav_page[(f)*4+:4]<=4;4:p_nav_page[(f)*4+:4]<=6;default:p_nav_page[(f)*4+:4]<=7;endcase
                        end                    end else if(decode_pages[f*4+:4]==6)begin
                        candidate=ACTION;
                        for(k=0;k<5;k=k+1)if(px>=48&&px<656&&py>=96+k*60&&py<148+k*60)p_command[(f)*32+:32]<={8'd14,21'd0,k[2:0]};
                    end else if(decode_pages[f*4+:4]==3&&py>=368&&py<424)begin
                        candidate=ACTION;if(px>=64&&px<312)p_command[(f)*32+:32]<={8'd2,24'd0};else if(px>=352&&px<624)p_command[(f)*32+:32]<={8'd3,24'd0};
                    end else if(decode_pages[f*4+:4]==7)begin
                        candidate=ACTION;
                        if(!game_running)for(k=0;k<6;k=k+1)if(px>=16&&px<672&&py>=80+k*28&&py<104+k*28)p_command[(f)*32+:32]<=32'h0f000000|k;
                        if(!game_running&&py>=232&&py<258)begin
                            if(px>=16&&px<208)p_command[(f)*32+:32]<=32'h06000000;else if(px>=240&&px<432)p_command[(f)*32+:32]<=32'h07000000;
                        end
                        if(py>=264&&py<380)candidate=KEY;
                        if(py>=400&&py<432)begin
                            candidate=ACTION;if(px>=16&&px<208)p_command[(f)*32+:32]<=32'h10000000;
                            else if(px>=240&&px<432)p_command[(f)*32+:32]<=32'h11000000;
                            else if(px>=464&&px<672)p_command[(f)*32+:32]<=32'h12000000;
                        end
                    end else if(decode_pages[f*4+:4]==4)begin
                        candidate=ACTION;
                        if(!usb_exported)for(k=0;k<6;k=k+1)if(px>=16&&px<672&&py>=96+k*44&&py<136+k*44)p_command[(f)*32+:32]<=32'h04000000|k;
                        if(!usb_exported&&py>=376&&py<424)begin
                            if(px>=16&&px<144)p_command[(f)*32+:32]<={8'd5,24'd0};else if(px>=176&&px<304)p_command[(f)*32+:32]<={8'd6,24'd0};
                            else if(px>=336&&px<464)p_command[(f)*32+:32]<={8'd7,24'd0};else if(px>=496&&px<624)p_command[(f)*32+:32]<={8'd8,24'd0};
                        end
                        if(px>=480&&px<672&&py>=72&&py<94)p_command[(f)*32+:32]<=32'h13000000;
                    end else if(decode_pages[f*4+:4]==5)begin
                        candidate=ACTION;
                        if(px>=48&&px<656&&py>=288&&py<320)candidate=SEEK;
                        else if(py>=352&&py<416)begin
                            if(px>=48&&px<208)p_command[(f)*32+:32]<={8'd12,24'd0};else if(px>=240&&px<400)p_command[(f)*32+:32]<={8'd9,24'd0};else if(px>=432&&px<592)p_command[(f)*32+:32]<={8'd13,24'd0};
                        end else if(py>=224&&py<268)begin
                            if(px>=48&&px<208)p_command[(f)*32+:32]<={8'd10,24'd0};else if(px>=240&&px<400)begin p_nav[f]<=1;p_nav_force[f]<=1;p_nav_page[(f)*4+:4]<=4;end
                        end
                    end else if(decode_pages[f*4+:4]>=1&&decode_pages[f*4+:4]<=3)candidate=KEY;
                    if(matched_now&&previous_role>=6&&previous_role<=8)p_seek[f*10+:10]<=(px<=208)?0:(px>=608)?100:(px-208)>>2;
                    p_role[(f)*4+:4]<=candidate;
                end
            end
        end
    end
    // 第二级只判定五指归属；第三级提交按键/命令，避免归属优先链继续串接导航清理链。
    reg q_pending;reg [4:0] q_active,q_nav,q_nav_force,q_new_seek,q_action,q_volume_owner,q_tone_owner,q_seek_match;
    reg q_seek_present,q_volume_next,q_tone_next;reg [7:0] q_volume_next_id,q_tone_next_id;
    reg [39:0] q_ids;reg [49:0] q_xs;
    reg [19:0] q_role,q_nav_page;reg [24:0] q_key;
    reg [34:0] q_volume;reg signed [19:0] q_tone;
    reg [49:0] q_seek;reg [159:0] q_command;
    integer a;reg av,at;reg [7:0] av_id,at_id;reg [2:0] av_slot,at_slot;reg [3:0] arole;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)q_pending<=0;else q_pending<=frame_pending&&connected&&!nav_valid;
    end
    always @(posedge clk)if(frame_pending)begin
        q_active<=p_active;q_ids<=p_ids;q_xs<=p_xs;q_nav<=p_nav;q_nav_force<=p_nav_force;
        q_seek_match<=p_seek_match;q_seek_present<=p_seek_present;
        av=volume_owned&&p_volume_present;at=tone_owned&&p_tone_present;
        av_id=volume_id;at_id=tone_id;av_slot=7;at_slot=7;
        for(a=0;a<5;a=a+1)begin
            arole=BLOCK;q_new_seek[a]<=0;q_action[a]<=0;
            if(p_active[a])begin
                if(p_matched[a])arole=p_old_role[(a)*4+:4];
                else begin
                    arole=p_role[(a)*4+:4];
                    if(arole==VOLUME)begin
                        if(!av)begin av=1;av_id=p_ids[a*8+:8];av_slot=a;end else arole=BLOCK;
                    end else if(arole==TONE)begin
                        if(!at)begin at=1;at_id=p_ids[a*8+:8];at_slot=a;end else arole=BLOCK;
                    end else if(arole==SEEK)begin
                        if(!seek_owned)q_new_seek[a]<=1;else arole=ACTION;
                    end else if(arole==ACTION)q_action[a]<=1;
                end
            end
            q_role[(a)*4+:4]<=arole;q_key[(a)*5+:5]<=p_key[(a)*5+:5];q_volume[(a)*7+:7]<=p_volume[(a)*7+:7];q_tone[(a)*4+:4]<=p_tone[(a)*4+:4];
            q_seek[(a)*10+:10]<=p_seek[(a)*10+:10];q_command[(a)*32+:32]<=p_command[(a)*32+:32];q_nav_page[(a)*4+:4]<=p_nav_page[(a)*4+:4];
        end
        q_volume_next<=av;q_tone_next<=at;q_volume_next_id<=av_id;q_tone_next_id<=at_id;
        for(a=0;a<5;a=a+1)begin
            q_volume_owner[a]<=av&&((av_slot==7)?p_volume_match[a]:p_equal[a*5+av_slot]);
            q_tone_owner[a]<=at&&((at_slot==7)?p_tone_match[a]:p_equal[a*5+at_slot]);
        end
    end
    integer i,j,c,r,match_index,xx,yy,idx;
    reg [27:0] next_keys;reg [3:0] role,action_page;reg nav,issued,volume_present,tone_present,seek_present;
    reg volume_next,tone_next;reg [7:0] volume_next_id,tone_next_id;reg [2:0] volume_slot,tone_slot;
    task emit(input [7:0] cmd,input [23:0] arg);
        begin if(!issued)begin command_valid<=1;command<={cmd,arg};issued=1;end end
    endtask
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            touch_keys<=0;volume_percent<=25;page<=1;decode_pages<={5{4'd1}};transpose_set_valid<=0;transpose_set<=0;
            command_valid<=0;command<=0;timbre_selected<=0;validation_run<=0;validation_count<=32;fx_enabled<=0;fx_levels<={7'd35,7'd35,7'd40};old_active<=0;volume_owned<=0;tone_owned<=0;seek_owned<=0;
            volume_id<=0;tone_id<=0;seek_id<=0;seek_value<=0;
            for(i=0;i<5;i=i+1)begin old_id[(i)*8+:8]<=0;old_role[(i)*4+:4]<=BLOCK;end
        end else begin
            transpose_set_valid<=0;command_valid<=0;
            if(!connected)begin touch_keys<=0;old_active<=0;volume_owned<=0;tone_owned<=0;seek_owned<=0;end
            else if(q_pending&&!nav_valid)begin
                next_keys=0;nav=0;action_page=page;issued=0;
                if(seek_owned&&!q_seek_present)begin emit(8'd11,{14'd0,seek_value});seek_owned<=0;end
                for(i=0;i<5;i=i+1)begin
                    role=q_role[(i)*4+:4];xx=q_xs[i*10+:10];
                    if(q_active[i])begin
                        if(q_new_seek[i])begin seek_owned<=1;seek_id<=q_ids[i*8+:8];seek_value<=q_seek[(i)*10+:10];end
                        if(q_action[i])begin
                            if(q_nav[i])begin if(!nav||q_nav_force[i])begin nav=1;action_page=q_nav_page[(i)*4+:4];end end
                            else if(q_command[(i)*32+24+:8]==14)begin
                                // 音色只在新触点按下时改变，持续按住/滑动不会重复触发。
                                if(!issued&&q_command[(i)*32+0+:3]<=4)begin timbre_selected<=q_command[(i)*32+0+:3];issued=1;end
                            end else if(ENABLE_EXTRA_APPS&&q_command[i*32+24+:8]==32)begin
                                if(!issued)begin if(q_command[i*32+:6]==0)validation_run<=!validation_run;else validation_count<=q_command[i*32+:6];issued=1;end
                            end else if(ENABLE_EXTRA_APPS&&q_command[i*32+24+:8]==33)begin
                                if(!issued&&q_command[i*32+:2]<3)begin fx_enabled[q_command[i*32+:2]]<=!fx_enabled[q_command[i*32+:2]];issued=1;end
                            end else if(q_command[(i)*32+24+:8]!=0)emit(q_command[(i)*32+24+:8],q_command[(i)*32+0+:24]);
                        end
                        if(role==VOLUME&&q_volume_owner[i])volume_percent<=q_volume[(i)*7+:7];
                        if(role==TONE&&page!=5&&q_tone_owner[i])begin transpose_set<=q_tone[(i)*4+:4];transpose_set_valid<=1;end
                        if(role==SEEK&&seek_owned&&q_seek_match[i])seek_value<=q_seek[(i)*10+:10];
                        if(ENABLE_EXTRA_APPS&&role>=6&&role<=8)fx_levels[(role-6)*7+:7]<=q_seek[i*10+:7];
                        if(role==KEY&&xx>=16&&xx<688)begin idx=q_key[(i)*5+:5];if(idx<28)next_keys[idx]=1;end
                    end
                    old_id[(i)*8+:8]<=q_ids[i*8+:8];old_role[(i)*4+:4]<=role;
                end
                old_active<=q_active;volume_owned<=q_volume_next;volume_id<=q_volume_next_id;tone_owned<=q_tone_next;tone_id<=q_tone_next_id;
                if(nav&&!(usb_exported&&page==4))begin
                    page<=action_page;decode_pages<={5{action_page}};touch_keys<=0;seek_owned<=0;
                    validation_run<=0;emit(8'd1,{20'd0,action_page});
                    for(i=0;i<5;i=i+1)if(!(q_volume_owner[i]||q_tone_owner[i]))old_role[(i)*4+:4]<=BLOCK;
                end else touch_keys<=next_keys;
            end
            if(nav_valid)begin
                validation_run<=0;page<=nav_page;decode_pages<={5{nav_page}};touch_keys<=0;seek_owned<=0;
                for(i=0;i<5;i=i+1)if(old_role[(i)*4+:4]!=VOLUME&&old_role[(i)*4+:4]!=TONE)old_role[(i)*4+:4]<=BLOCK;
            end
        end
    end
endmodule
