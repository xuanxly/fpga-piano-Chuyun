`timescale 1ns/1ps
// D12 实时判定器：CPU只提交谱面，计时/和弦/长按/评分/灯光提示均在本模块完成。
// 事件格式：绝对毫秒、28位琴键掩码、持续毫秒；最后一项使用end标记。
module d12_game_timing_reference #(
    parameter integer CLK_HZ=50000000,COUNTDOWN_MS=3000,LEAD_MS=150,WINDOW_MS=150
)(
    input wire clk,rst_n,page_active,input wire [27:0] keys,
    input wire write,input wire [5:0] address,input wire [31:0] wdata,
    output reg [31:0] rdata,output wire [159:0] status,
    output wire guide_active,output wire [27:0] guide_keys,good_keys,bad_keys
);
    // 五分钟谱面时间只需19位；事件恰好64位，减少队列及28路长音比较器的布线。
    localparam integer MS_BITS=(CLK_HZ/1000>1)?$clog2(CLK_HZ/1000):1;
    // 小型分布式队列。满时拒绝写入并报告错误，不覆盖旧谱面。
    (* syn_ramstyle="distributed_ram" *) reg [63:0] queue[0:31];
    reg [4:0] wp,rp;reg [5:0] count;reg [18:0] stage_time;reg [31:0] stage_mask,stage_duration;
    reg running,paused,practice,complete,fault,valid;
    reg [18:0] now_ms,cur_time;reg [19:0] score;reg [MS_BITS-1:0] ms_div;
    reg [18:0] window_begin,window_end,guide_begin,perfect_begin,perfect_end;
    reg [15:0] cur_duration,cur_early_duration,combo,hits,misses,countdown;
    reg [27:0] cur_mask,hit_mask,hold_mask,old_keys,pending_edges;
    reg [18:0] hold_end[0:27],hold_early_end[0:27];reg cur_end;
    reg [27:0] flash_good,flash_bad;reg [7:0] flash_ms;
    wire clear=write&&address==0&&wdata[2];
    wire push=write&&address==16&&count<32&&!clear;
    wire pop=!valid&&count!=0&&!clear;
    wire tick=ms_div==CLK_HZ/1000-1;
    wire waiting=running&&!valid&&count==0&&!complete;
    wire [27:0] edges_now=pending_edges|(keys&~old_keys);
    wire [27:0] accepted=hit_mask|(edges_now&cur_mask);
    // 队首装载时预计算窗口，毫秒判定只做比较，切断“加法->比较->和弦->28路使能”长路径。
    wire [18:0] queued_time=queue[rp][18:0];
    wire in_window=valid&&!cur_end&&(now_ms>=window_begin)&&(practice||now_ms<=window_end);
    wire chord_hit=in_window&&accepted==cur_mask&&(keys&cur_mask)==cur_mask&&cur_mask!=0;
    wire [27:0] wrong_edges=edges_now&~(hold_mask|(in_window?cur_mask:28'd0));
    wire perfect=now_ms>=perfect_begin&&now_ms<=perfect_end;
    assign guide_active=running&&page_active;
    // 提示只在倒计时结束后出现；提前量与判定窗口一致，看到灯就可以按。
    assign guide_keys=guide_active&&countdown==0&&!paused?(hold_mask|((valid&&!cur_end&&now_ms>=guide_begin)?cur_mask:28'd0)):28'd0;
    assign good_keys=guide_active&&countdown==0&&!paused?(flash_good|hold_mask):28'd0;
    assign bad_keys=guide_active&&countdown==0&&!paused?flash_bad:28'd0;
    // 十进制逐位转换分20拍完成，避免在像素时钟域放置大除法器。
    reg [19:0] bcd_source,bcd_binary;reg [23:0] score_bcd,bcd_work;
    reg [4:0] bcd_count;reg bcd_busy;reg [23:0] bcd_adjusted;
    integer digit;
    always @*begin
        bcd_adjusted=bcd_work;
        for(digit=0;digit<6;digit=digit+1)if(bcd_work[digit*4+:4]>=5)bcd_adjusted[digit*4+:4]=bcd_work[digit*4+:4]+4'd3;
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin bcd_source<=0;bcd_binary<=0;score_bcd<=0;bcd_work<=0;bcd_count<=0;bcd_busy<=0;end
        else if(!bcd_busy)begin
            if(bcd_source!=score[19:0])begin bcd_source<=score[19:0];bcd_binary<=score[19:0];bcd_work<=0;bcd_count<=0;bcd_busy<=1;end
        end else begin
            bcd_work<={bcd_adjusted[22:0],bcd_binary[19]};bcd_binary<=bcd_binary<<1;bcd_count<=bcd_count+1'b1;
            if(bcd_count==19)begin score_bcd<={bcd_adjusted[22:0],bcd_binary[19]};bcd_busy<=0;end
        end
    end
    // 5个32位画面快照字：提示键、BCD分数、命中/漏音、连击/倒计时、标志/队列空位。
    wire [31:0] flags={10'd0,(6'd32-count),10'd0,fault,complete,waiting,practice,paused,running};
    assign status={flags,{countdown,combo},{misses,hits},{8'd0,score_bcd},{4'd0,guide_keys}};
    always @*begin
        case(address)
            0:rdata=flags;4:rdata=now_ms;8:rdata=score;12:rdata={misses,hits};
            16:rdata={countdown,combo};20:rdata=cur_time;24:rdata={4'd0,guide_keys};
            default:rdata=0;
        endcase
    end
    integer i;reg dropped_hold;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            wp<=0;rp<=0;count<=0;stage_time<=0;stage_mask<=0;stage_duration<=0;
            running<=0;paused<=0;practice<=1;complete<=0;fault<=0;valid<=0;cur_end<=0;
            now_ms<=0;score<=0;ms_div<=0;cur_time<=0;cur_duration<=0;cur_early_duration<=0;cur_mask<=0;
            window_begin<=0;window_end<=0;guide_begin<=0;perfect_begin<=0;perfect_end<=0;
            combo<=0;hits<=0;misses<=0;countdown<=0;hit_mask<=0;hold_mask<=0;
            old_keys<=0;pending_edges<=0;flash_good<=0;flash_bad<=0;flash_ms<=0;
            for(i=0;i<28;i=i+1)begin hold_end[i]<=0;hold_early_end[i]<=0;end
        end else begin
            old_keys<=keys;
            pending_edges<=running&&!paused&&countdown==0?(pending_edges|(keys&~old_keys)):28'd0;
            if(tick)ms_div<=0;else ms_div<=ms_div+1'b1;
            if(write&&address==4)stage_time<=wdata[18:0];
            if(write&&address==8)stage_mask<=wdata;
            if(write&&address==12)stage_duration<=wdata;
            if(write&&address==16&&count==32)fault<=1;
            case({push,pop})2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;default:begin end endcase
            if(push)begin queue[wp]<={stage_mask[31],stage_duration[15:0],stage_mask[27:0],stage_time};wp<=wp+1'b1;end
            if(pop)begin
                {cur_end,cur_duration,cur_mask,cur_time}<=queue[rp];rp<=rp+1'b1;valid<=1;hit_mask<=0;
                window_begin<=queued_time>WINDOW_MS?queued_time-WINDOW_MS:19'd0;
                window_end<=queued_time+WINDOW_MS;
                guide_begin<=queued_time>LEAD_MS?queued_time-LEAD_MS:19'd0;
                perfect_begin<=queued_time>50?queued_time-19'd50:19'd0;perfect_end<=queued_time+19'd50;
                // 长音才使用此字段（音长>300ms），提前算出60ms释放宽限的偏移。
                cur_early_duration<=queue[rp][62:47]-16'd60;
            end
            if(write&&address==0&&!clear)begin
                running<=wdata[0]&&page_active;paused<=wdata[1];practice<=wdata[3];
                if(wdata[0]&&!running)begin countdown<=COUNTDOWN_MS;complete<=0;pending_edges<=0;end
            end
            if(!page_active)begin running<=0;hold_mask<=0;flash_good<=0;flash_bad<=0;pending_edges<=0;end
            if(tick)begin
                pending_edges<=0;
                if(flash_ms!=0)flash_ms<=flash_ms-1'b1;else begin flash_good<=0;flash_bad<=0;end
                if(running&&!paused&&page_active)begin
                    if(countdown!=0)countdown<=countdown-1'b1;
                    else if(!waiting)begin
                        // 练习模式在目标时刻等待；挑战模式按固定时钟继续。
                        if(!(practice&&valid&&!cur_end&&now_ms>=cur_time&&!chord_hit))now_ms<=now_ms+1'b1;
                        if(in_window)hit_mask<=accepted;
                        dropped_hold=0;
                        for(i=0;i<28;i=i+1)if(hold_mask[i])begin
                            // 下一次同键已进入可按窗口时允许松开再触发，不把换音当作提前释放。
                            if(now_ms>=hold_end[i]||(valid&&!cur_end&&cur_mask[i]&&now_ms>=window_begin))hold_mask[i]<=0;
                            else if(!keys[i]&&now_ms<hold_early_end[i])begin hold_mask[i]<=0;dropped_hold=1;end
                        end
                        if(chord_hit)begin
                            valid<=0;hits<=hits+1'b1;combo<=combo==65535?combo:combo+1'b1;
                            if(score<999800)score<=score+((practice||perfect)?100:70);
                            flash_good<=cur_mask;flash_bad<=0;flash_ms<=160;
                            // 两个绝对截止时刻各自寄存；判定时不再把“now+60”加法串到28路归并后面。
                            if(cur_duration>300)for(i=0;i<28;i=i+1)if(cur_mask[i])begin
                                hold_mask[i]<=1;hold_end[i]<=now_ms+cur_duration;hold_early_end[i]<=now_ms+cur_early_duration;
                            end
                        end else if(valid&&!cur_end&&!practice&&now_ms>window_end)begin
                            valid<=0;misses<=misses+1'b1;combo<=0;flash_bad<=cur_mask;flash_ms<=160;
                        end
                        if(wrong_edges!=0||dropped_hold)begin
                            misses<=misses+1'b1;combo<=0;flash_bad<=wrong_edges;flash_ms<=160;
                        end
                        if(valid&&cur_end&&now_ms>=cur_time&&hold_mask==0)begin running<=0;complete<=1;valid<=0;end
                        // 谱面仍限制5分钟；尾音保留一次迟按窗口和EOF收尾余量。
                        if(now_ms>=300500)begin running<=0;fault<=1;end
                    end
                end
            end
            if(clear)begin
                wp<=0;rp<=0;count<=0;running<=0;paused<=0;practice<=wdata[3];complete<=0;fault<=0;valid<=0;
                now_ms<=0;score<=0;combo<=0;hits<=0;misses<=0;countdown<=0;hold_mask<=0;hit_mask<=0;
                flash_good<=0;flash_bad<=0;flash_ms<=0;pending_edges<=0;
            end
        end
    end
endmodule
