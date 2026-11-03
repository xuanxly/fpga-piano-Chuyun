`timescale 1ns/1ps
// 实屏WS170120，VID=0EEF/PID=0005：2026-10-29 Windows HID能力表与7302条实测报告。
// 每包11字节，一包一个触点；首包ContactCount给出整帧包数，续包为0，同帧ScanTime相同。
// 仅接收USB层已经核对长度、CRC及DATA toggle后的新包；NAK和重传不能当成松手。
module ws170120_reports #(
    parameter integer INCOMPLETE_CYCLES=6000000 // 60MHz下100ms，只约束未收齐的帧。
)(
    input wire clk,rst_n,connected,report_valid,
    input wire [6:0] report_length,input wire [87:0] report_data,
    output reg frame_valid,output reg [4:0] active,
    output reg [39:0] ids,output reg [49:0] xs,ys,
    output reg protocol_error
);
    wire [7:0] rid=report_data[7:0],cid=report_data[23:16],count=report_data[87:80];
    wire tip=report_data[8];
    wire [15:0] xx=report_data[47:32],yy=report_data[63:48],stamp=report_data[79:64];
    reg collecting,have_completed;reg [15:0] collecting_stamp,completed_stamp;
    reg [87:0] collecting_first,completed_first; // ScanTime不是USB序号；新DATA的同时间戳坐标/松手仍须处理。
    reg [2:0] wanted,received;reg [31:0] age;
    reg [4:0] work_active;reg [39:0] work_ids;reg [49:0] work_xs,work_ys;
    reg [4:0] next_active;reg [39:0] next_ids;reg [49:0] next_xs,next_ys;
    reg duplicate;integer i,slot;
    wire valid_fields=report_length==11 && rid==1 && count<=5 && (!tip || (xx<=800 && yy<=480));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            frame_valid<=0;active<=0;ids<=0;xs<=0;ys<=0;protocol_error<=0;
            collecting<=0;have_completed<=0;collecting_stamp<=0;completed_stamp<=0;collecting_first<=0;completed_first<=0;
            wanted<=0;received<=0;age<=0;work_active<=0;work_ids<=0;work_xs<=0;work_ys<=0;
        end else begin
            frame_valid<=0;
            if(!connected) begin
                collecting<=0;have_completed<=0;active<=0;ids<=0;xs<=0;ys<=0;age<=0;
            end else begin
                if(collecting) begin
                    if(age==INCOMPLETE_CYCLES-1) begin
                        // 丢弃未完成的新帧，保留最后完整帧；缺续包不等于用户松手。
                        // 显式Tip=0或真实拔出仍立即释放，不延长已收到的松手事件。
                        collecting<=0;protocol_error<=1;age<=0;
                    end else age<=age+1'b1;
                end
                if(report_valid) begin
                    if(!valid_fields) begin
                        protocol_error<=1; // 错误数据不改写上一份完整快照。
                    end else if(count!=0) begin
                        if(!(have_completed && count==1 && stamp==completed_stamp && report_data==completed_first) &&
                           !(collecting && stamp==collecting_stamp && report_data==collecting_first)) begin
                            next_active=0;next_ids=0;next_xs=0;next_ys=0;
                            next_active[0]=tip;next_ids[7:0]=cid;
                            next_xs[9:0]=(xx==800)?799:xx[9:0];
                            next_ys[9:0]=(yy==480)?479:yy[9:0];
                            work_active<=next_active;work_ids<=next_ids;work_xs<=next_xs;work_ys<=next_ys;
                            wanted<=count[2:0];received<=1;collecting_stamp<=stamp;collecting_first<=report_data;age<=0;
                            if(count==1) begin
                                active<=next_active;ids<=next_ids;xs<=next_xs;ys<=next_ys;frame_valid<=1;
                                collecting<=0;have_completed<=1;completed_stamp<=stamp;completed_first<=report_data;
                            end else collecting<=1;
                        end // 只忽略同时间戳且内容完全相同的重复单触点/正在收集的首包。
                    end else if(collecting && stamp==collecting_stamp) begin
                        duplicate=0;
                        for(i=0;i<5;i=i+1) if(i<received && work_ids[i*8+:8]==cid) duplicate=1;
                        if(!duplicate && received<5) begin
                            slot=received;next_active=work_active;next_ids=work_ids;next_xs=work_xs;next_ys=work_ys;
                            next_active[slot]=tip;next_ids[slot*8+:8]=cid;
                            next_xs[slot*10+:10]=(xx==800)?799:xx[9:0];
                            next_ys[slot*10+:10]=(yy==480)?479:yy[9:0];
                            work_active<=next_active;work_ids<=next_ids;work_xs<=next_xs;work_ys<=next_ys;
                            received<=received+1'b1;
                            if(received+1==wanted) begin
                                active<=next_active;ids<=next_ids;xs<=next_xs;ys<=next_ys;frame_valid<=1;
                                collecting<=0;have_completed<=1;completed_stamp<=stamp;completed_first<=collecting_first;
                            end
                        end
                    end else if(!collecting&&!tip)begin
                        // 首包丢失时，可信Tip=0仍可释放已知ID；不将孤立Tip=1当成新按下。
                        next_active=active;
                        for(i=0;i<5;i=i+1)if(active[i]&&ids[i*8+:8]==cid)next_active[i]=0;
                        if(next_active!=active)begin active<=next_active;frame_valid<=1;have_completed<=0;end
                    end
                end
            end
        end
    end
endmodule

// 有握手的跨时钟快照；USB侧来不及发送时保留最新完整帧，永不改写正在跨域的数据。
module touch_frame_cdc(
    input wire src_clk,src_rst_n,src_connected,src_valid,input wire [4:0] src_active,
    input wire [39:0] src_ids,input wire [49:0] src_xs,src_ys,
    input wire dst_clk,dst_rst_n,output reg dst_connected,dst_valid,
    output reg [4:0] dst_active,output reg [39:0] dst_ids,output reg [49:0] dst_xs,dst_ys
);
    reg [145:0] held_data,pending_data;
    reg request,pending,old_connected;reg ack;
    (* syn_preserve=1, ASYNC_REG="TRUE" *) reg ack_meta,ack_sync,req_meta,req_sync;
    wire event_now=src_valid || src_connected!=old_connected;
    always @(posedge src_clk or negedge src_rst_n) begin
        if(!src_rst_n) begin
            held_data<=0;pending_data<=0;request<=0;pending<=1;old_connected<=0;ack_meta<=0;ack_sync<=0;
        end else begin
            ack_meta<=ack;ack_sync<=ack_meta;old_connected<=src_connected;
            if(pending && ack_sync==request) begin held_data<=pending_data;request<=~request;pending<=0;end
            if(event_now) begin
                pending<=1;pending_data<={src_connected,src_connected?src_active:5'd0,src_ids,src_xs,src_ys};
            end
        end
    end
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if(!dst_rst_n) begin req_meta<=0;req_sync<=0;ack<=0;dst_valid<=0;dst_connected<=0;dst_active<=0;dst_ids<=0;dst_xs<=0;dst_ys<=0;end
        else begin
            req_meta<=request;req_sync<=req_meta;dst_valid<=0;
            if(req_sync!=ack) begin
                {dst_connected,dst_active,dst_ids,dst_xs,dst_ys}<=held_data;dst_valid<=1;ack<=req_sync;
            end
        end
    end
endmodule
