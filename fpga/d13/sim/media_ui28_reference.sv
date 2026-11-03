`timescale 1ns/1ps
// 六页应用UI：录音与文件命令发往CPU，触摸键/双柱仍在50MHz硬件中即时处理。
module media_ui28_reference(input wire clk,rst_n,frame_valid,connected,input wire [4:0] active,
    input wire [39:0] ids,input wire [49:0] xs,ys,input wire nav_valid,input wire [2:0] nav_page,
    output reg [27:0] touch_keys,output reg [6:0] volume_percent,output reg [2:0] page,
    output reg transpose_set_valid,output reg signed [3:0] transpose_set,
    output reg command_valid,output reg [31:0] command);
    localparam BLOCK=0,KEY=1,VOLUME=2,ACTION=3,TONE=4,SEEK=5;
    reg [4:0] old_active;reg [7:0] old_id[0:4];reg [2:0] old_role[0:4];
    reg volume_owned,tone_owned,seek_owned;reg [7:0] volume_id,tone_id,seek_id;reg [9:0] seek_value;
    function [4:0] key_at(input [2:0] p,input [9:0] px,py);
        integer c,r,found_c,found_r;begin
            found_c=-1;found_r=-1;
            for(c=0;c<7;c=c+1) if(px>=16+c*96 && px<106+c*96) found_c=c;
            for(r=0;r<4;r=r+1) begin
                if(p==1 && py>=304+r*28 && py<328+r*28) found_r=r;
                if(p==2 && py>=96+r*80 && py<170+r*80) found_r=r;
                if(p==3 && py>=96+r*60 && py<150+r*60) found_r=r;
            end
            key_at=(found_c>=0 && found_r>=0)?found_r*7+found_c:5'd31;
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

    integer i,j,c,r,match_index,xx,yy,idx;
    reg [27:0] next_keys;reg [2:0] role,action_page;reg nav,issued,volume_present,tone_present,seek_present;
    reg volume_next,tone_next;reg [7:0] volume_next_id,tone_next_id;
    task emit(input [7:0] cmd,input [23:0] arg);
        begin if(!issued)begin command_valid<=1;command<={cmd,arg};issued=1;end end
    endtask
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            touch_keys<=0;volume_percent<=25;page<=1;transpose_set_valid<=0;transpose_set<=0;
            command_valid<=0;command<=0;old_active<=0;volume_owned<=0;tone_owned<=0;seek_owned<=0;
            volume_id<=0;tone_id<=0;seek_id<=0;seek_value<=0;
            for(i=0;i<5;i=i+1)begin old_id[i]<=0;old_role[i]<=BLOCK;end
        end else begin
            transpose_set_valid<=0;command_valid<=0;
            if(!connected)begin touch_keys<=0;old_active<=0;volume_owned<=0;tone_owned<=0;seek_owned<=0;end
            else if(frame_valid)begin
                next_keys=0;nav=0;action_page=page;issued=0;volume_present=0;tone_present=0;seek_present=0;
                for(i=0;i<5;i=i+1)begin
                    if(active[i]&&ids[i*8+:8]==volume_id)volume_present=1;
                    if(active[i]&&ids[i*8+:8]==tone_id)tone_present=1;
                    if(active[i]&&ids[i*8+:8]==seek_id)seek_present=1;
                end
                volume_next=volume_owned&&volume_present;volume_next_id=volume_id;
                tone_next=tone_owned&&tone_present;tone_next_id=tone_id;
                if(seek_owned&&!seek_present)begin emit(8'd11,{14'd0,seek_value});seek_owned<=0;end
                for(i=0;i<5;i=i+1)begin
                    role=BLOCK;match_index=-1;xx=xs[i*10+:10];yy=ys[i*10+:10];
                    for(j=0;j<5;j=j+1)if(old_active[j]&&old_id[j]==ids[i*8+:8])match_index=j;
                    if(active[i])begin
                        if(match_index>=0)role=old_role[match_index];
                        else if(xx>=704&&xx<750&&yy>=48&&yy<416)begin
                            if(!volume_next)begin role=VOLUME;volume_next=1;volume_next_id=ids[i*8+:8];end
                        end else if(page!=5&&xx>=754&&xx<800&&yy>=48&&yy<416)begin
                            if(!tone_next)begin role=TONE;tone_next=1;tone_next_id=ids[i*8+:8];end
                        end else if(xx>=704&&xx<792&&yy>=432&&yy<476)begin role=ACTION;if(!nav)begin nav=1;action_page=0;end end
                        else if(page==0)begin
                            role=ACTION;
                            if(!nav&&yy>=96&&yy<232)begin
                                if(xx>=80&&xx<336)begin nav=1;action_page=1;end
                                else if(xx>=384&&xx<640)begin nav=1;action_page=2;end
                            end else if(!nav&&yy>=256&&yy<392)begin
                                if(xx>=80&&xx<336)begin nav=1;action_page=3;end
                                else if(xx>=384&&xx<640)begin nav=1;action_page=4;end
                            end
                        end else if(page==3&&yy>=368&&yy<424)begin
                            role=ACTION;if(xx>=64&&xx<312)emit(8'd2,0);else if(xx>=352&&xx<624)emit(8'd3,0);
                        end else if(page==4)begin
                            role=ACTION;
                            for(c=0;c<6;c=c+1)if(xx>=16&&xx<672&&yy>=96+c*44&&yy<136+c*44)emit(8'd4,c);
                            if(yy>=376&&yy<424)begin
                                if(xx>=16&&xx<144)emit(8'd5,0);else if(xx>=176&&xx<304)emit(8'd6,0);
                                else if(xx>=336&&xx<464)emit(8'd7,0);else if(xx>=496&&xx<624)emit(8'd8,0);
                            end
                        end else if(page==5)begin
                            role=ACTION;
                            if(xx>=48&&xx<656&&yy>=288&&yy<320&&!seek_owned)begin
                                role=SEEK;seek_owned<=1;seek_id<=ids[i*8+:8];seek_value<=seek_at(xs[i*10+:10]);
                            end else if(yy>=352&&yy<416)begin
                                if(xx>=48&&xx<208)emit(8'd12,0);else if(xx>=240&&xx<400)emit(8'd9,0);else if(xx>=432&&xx<592)emit(8'd13,0);
                            end else if(yy>=224&&yy<268)begin
                                if(xx>=48&&xx<208)emit(8'd10,0);else if(xx>=240&&xx<400)begin nav=1;action_page=4;end
                            end
                        end else if(page>=1&&page<=3)role=KEY;
                        if(role==VOLUME&&volume_next&&ids[i*8+:8]==volume_next_id)volume_percent<=volume_at(ys[i*10+:10]);
                        if(role==TONE&&page!=5&&tone_next&&ids[i*8+:8]==tone_next_id)begin transpose_set<=tone_at(ys[i*10+:10]);transpose_set_valid<=1;end
                        if(role==SEEK&&seek_owned&&ids[i*8+:8]==seek_id)seek_value<=seek_at(xs[i*10+:10]);
                        if(role==KEY&&xx>=16&&xx<688)begin idx=key_at(page,xs[i*10+:10],ys[i*10+:10]);if(idx<28)next_keys[idx]=1;end
                    end
                    old_id[i]<=ids[i*8+:8];old_role[i]<=role;
                end
                old_active<=active;volume_owned<=volume_next;volume_id<=volume_next_id;tone_owned<=tone_next;tone_id<=tone_next_id;
                if(nav)begin
                    page<=action_page;touch_keys<=0;seek_owned<=0;
                    emit(8'd1,{21'd0,action_page});
                    for(i=0;i<5;i=i+1)if(!((volume_next&&ids[i*8+:8]==volume_next_id)||(tone_next&&ids[i*8+:8]==tone_next_id)))old_role[i]<=BLOCK;
                end else touch_keys<=next_keys;
            end
            if(nav_valid)begin
                page<=nav_page;touch_keys<=0;seek_owned<=0;
                for(i=0;i<5;i=i+1)if(old_role[i]!=VOLUME&&old_role[i]!=TONE)old_role[i]<=BLOCK;
            end
        end
    end
endmodule
