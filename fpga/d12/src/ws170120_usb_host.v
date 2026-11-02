`timescale 1ns/1ps
// 单设备、直连Full-Speed主机，专门适配实测WS170120；不是通用USB/HID驱动。
// 设备/配置按电脑实际读取的描述符核对，EP0=64，接口0，Interrupt IN=0x82/3ms。
// 无Hub、鼠标、键盘、High-Speed支持；不发送Boot Protocol切换命令。
module ws170120_usb_host #(
    parameter integer ATTACH_CYCLES=6000000,RESET_CYCLES=1200000,RECOVERY_CYCLES=600000,
    parameter integer FRAME_CYCLES=60000,POLL_CYCLES=180000,DISCONNECT_CYCLES=150
)(
    input wire clk,rst_n,dp_i,dm_i,output wire dp_o,dm_o,oe,
    output reg connected,output reg report_valid,output reg [87:0] report_data,
    output reg [3:0] fault,output wire [7:0] debug_state,
    output wire [63:0] debug_info                 // D2：只观察USB流程，不改变事务/重试策略。
);
    localparam DETACHED=0,BUS_RESET=1,RECOVER=2,SETUP_START=10,SETUP_WAIT=11,
               IN_START=12,IN_WAIT=13,STATUS_START=14,STATUS_WAIT=15,VALIDATE=16,
               POLL_IDLE=19,POLL_START=20,POLL_WAIT=21,SOF_WAIT=30;
    reg [7:0] state,sof_return;assign debug_state=state;
    wire force_se0=state==BUS_RESET;
    wire phy_tx_busy,phy_tx_done,phy_rx_busy,phy_rx_valid,phy_rx_error,phy_crc;
    wire [6:0] phy_rx_length;wire [535:0] phy_rx_packet;wire [1:0] line_state;
    wire tx_start;wire [3:0] tx_length;wire [87:0] tx_packet;
    usb_fs_phy60 u_phy(clk,rst_n,dp_i,dm_i,force_se0,tx_start,tx_length,tx_packet,
        phy_tx_busy,phy_tx_done,dp_o,dm_o,oe,phy_rx_busy,phy_rx_valid,phy_rx_error,phy_crc,
        phy_rx_length,phy_rx_packet,line_state);
    reg tr_start;reg [1:0] tr_mode;reg [6:0] address;reg [3:0] endpoint,out_length;
    reg out_toggle;reg [63:0] out_data;wire tr_busy,tr_done;wire [2:0] result;
    wire [6:0] in_length;wire [511:0] in_data;wire in_toggle;
    localparam integer MAX_TIMER_A=(ATTACH_CYCLES>RESET_CYCLES)?ATTACH_CYCLES:RESET_CYCLES;
    localparam integer MAX_TIMER=(MAX_TIMER_A>RECOVERY_CYCLES)?MAX_TIMER_A:RECOVERY_CYCLES;
    localparam integer TIMER_BITS=(MAX_TIMER>1)?$clog2(MAX_TIMER):1;
    localparam integer FRAME_BITS=(FRAME_CYCLES>1)?$clog2(FRAME_CYCLES):1;
    localparam integer WAIT_BITS=(FRAME_CYCLES>0)?$clog2(2*FRAME_CYCLES+1):1;
    localparam integer POLL_BITS=(POLL_CYCLES>1)?$clog2(POLL_CYCLES):1;
    localparam integer DISCONNECT_BITS=(DISCONNECT_CYCLES>0)?$clog2(DISCONNECT_CYCLES+2):1;
    // 各门限保持不变，只保留实际需要的计数位宽，避免32位无效高位的进位链。
    reg [10:0] frame_number;reg [FRAME_BITS-1:0] frame_timer;reg sof_pending;
    // 独立寄存的事务复位许可，避免状态解码直接扇出到整包寄存器的异步CLEAR。
    reg transport_active;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)transport_active<=0;
        else transport_active<=state>=SETUP_START;
    end
    wire transport_reset_n=rst_n&&transport_active;
    usb_fs_transaction u_transaction(clk,transport_reset_n,tr_start,tr_mode,address,endpoint,out_length,out_toggle,out_data,
        frame_number,tr_busy,tr_done,result,in_length,in_data,in_toggle,tx_start,tx_length,tx_packet,
        phy_tx_done,phy_rx_busy,phy_rx_valid,phy_rx_error,phy_crc,phy_rx_length,phy_rx_packet);
    reg [TIMER_BITS-1:0] timer;reg [WAIT_BITS-1:0] wait_cycles;
    reg [POLL_BITS-1:0] poll_timer;reg [DISCONNECT_BITS-1:0] disconnect_timer;
    reg wait_ready,launch_window_q,disconnect_pending;
    reg [3:0] step;reg [9:0] retries;reg [3:0] failures;
    reg [7:0] received;reg control_toggle,poll_toggle;reg [327:0] descriptor;
    // 控制步骤在整笔SETUP/IN/STATUS事务中保持稳定；提前寄存解码结果，避免扇出到接收包写使能。
    reg control_read,store_descriptor;
    reg [7:0] control_length;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin control_read<=1;store_descriptor<=1;control_length<=8;end
        else begin
            control_read<=step==0||step==2||step==3||step==5;
            store_descriptor<=step!=5;
            control_length<=step==0?8:(step==2?18:(step==3?41:124));
        end
    end
    function [63:0] setup_request(input [3:0] s);
        begin case(s)
            0: setup_request=64'h0008000001000680; // GET_DESCRIPTOR(Device,8), addr0。
            1: setup_request=64'h0000000000010500; // SET_ADDRESS(1)，状态阶段仍在addr0。
            2: setup_request=64'h0012000001000680; // 完整设备描述符18字节。
            3: setup_request=64'h0029000002000680; // 完整配置描述符41字节。
            4: setup_request=64'h0000000000010900; // SET_CONFIGURATION(1)。
            5: setup_request=64'h007c000022000681; // 接口0的124字节HID报告描述符。
            6: setup_request=64'h0000000000000a21; // SET_IDLE(0)，允许非Boot设备STALL。
            default: setup_request=0;
        endcase end
    endfunction
    // 描述符在进入下一控制步骤前清零，避免等待计数/帧窗口直接驱动328位清零使能。
    wire profile_device=descriptor[7:0]==18 && descriptor[15:8]==1 && descriptor[63:56]==64 &&
        descriptor[79:64]==16'h0eef && descriptor[95:80]==16'h0005 && descriptor[111:96]==16'h0200 && descriptor[143:136]==1;
    // 各描述符按长度边界取字段；不要将IN端点误用为参考键鼠驱动默认的EP1。
    wire profile_config=descriptor[31:0]==32'h00290209 && descriptor[55:32]==24'h000101 &&
        descriptor[103:72]==32'h00000409 && descriptor[135:104]==32'h00000302 &&
        descriptor[151:136]==16'h0900 && descriptor[199:192]==8'h22 && descriptor[215:200]==16'd124 &&
        descriptor[247:216]==32'h03820507 && descriptor[271:248]==24'h030040 &&
        descriptor[303:272]==32'h03010507 && descriptor[327:304]==24'h030040;
    reg profile_device_q,profile_config_q;
    // 描述符在STATUS事务前已稳定；先寄存宽比较，VALIDATE不再串接宽比较与状态/计时清零。
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin profile_device_q<=0;profile_config_q<=0;end
        else begin profile_device_q<=profile_device;profile_config_q<=profile_config;end
    end
    // profile_config的精确断言另有真实41字节描述符回归；只支持已确认的这一配置。
    wire scheduler_state=state==SETUP_START || state==IN_START || state==STATUS_START || state==POLL_START || state==POLL_IDLE;
    // 帧尾预留足够时间完成一个最大64字节事务，避免控制传输把下一个1ms SOF推迟。
    localparam integer FRAME_GUARD=(FRAME_CYCLES>12000)?8000:(FRAME_CYCLES/2);
    wire launch_window=launch_window_q;
    reg [7:0] previous_state,last_failure_state,report_count,failure_count;
    reg [3:0] previous_fault,last_failure_step,last_failure_fault;
    reg [3:0] last_result;reg [7:0] last_length;
    reg [3:0] failure_result;reg [7:0] failure_length;
    reg seen_j,seen_tx,seen_rx;
    // 枚举计时器只依赖枚举阶段；事务成功/失败结果无需经过24位计数器反馈路径。
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)timer<=0;
        else case(state)
            DETACHED: if(line_state!=2'b10||timer==ATTACH_CYCLES-1)timer<=0;else timer<=timer+1'b1;
            BUS_RESET: if(timer==RESET_CYCLES-1)timer<=0;else timer<=timer+1'b1;
            RECOVER: if(timer==RECOVERY_CYCLES-1)timer<=0;else timer<=timer+1'b1;
            default:timer<=0;
        endcase
    end
    // 错误后状态机会自动重新枚举，因此单独保留失败前状态和步骤，防止照片错过瞬时错误。
    // 本寄存器组只在复位时清空；最后一次事务结果包括正常NAK，不等于最后一次失败。
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            previous_state<=0;previous_fault<=0;last_failure_state<=0;last_failure_step<=0;last_failure_fault<=0;
            report_count<=0;failure_count<=0;last_result<=0;last_length<=0;failure_result<=0;failure_length<=0;seen_j<=0;seen_tx<=0;seen_rx<=0;
        end else begin
            previous_state<=state;previous_fault<=fault;
            if(line_state==2'b10) seen_j<=1;
            if(phy_tx_busy) seen_tx<=1;
            if(phy_rx_valid) seen_rx<=1;
            if(tr_done) begin last_result<={1'b0,result};last_length<={1'b0,in_length};end
            if(report_valid) report_count<=report_count+1'b1;
            if(fault!=0 && previous_fault==0) begin
                last_failure_state<=previous_state;last_failure_step<=step;last_failure_fault<=fault;
                failure_result<=last_result;failure_length<=last_length;
                if(failure_count!=255) failure_count<=failure_count+1'b1;
            end
        end
    end
    // 出错后TR/LEN固定为该次失败上下文，不被后续重试或正常NAK覆盖。
    assign debug_info={connected,seen_rx,seen_tx,seen_j,failure_count,report_count,
                       (last_failure_fault!=0 ? failure_length:last_length),(last_failure_fault!=0 ? failure_result:last_result),
                       last_failure_fault,last_failure_step,last_failure_state,phy_tx_busy,phy_rx_busy,line_state,step,state};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=DETACHED;sof_return<=0;connected<=0;report_valid<=0;report_data<=0;fault<=0;
            tr_start<=0;tr_mode<=0;address<=0;endpoint<=0;out_length<=0;out_toggle<=0;out_data<=0;
            frame_number<=0;frame_timer<=0;sof_pending<=0;wait_cycles<=0;poll_timer<=0;disconnect_timer<=0;
            wait_ready<=1;launch_window_q<=1;disconnect_pending<=0;
            step<=0;retries<=0;failures<=0;received<=0;control_toggle<=1;poll_toggle<=0;descriptor<=0;
        end else begin
            tr_start<=0;report_valid<=0;
            // 计数到1时同时准备“已结束”标志；下一拍计数为0与原组合检测完全对齐。
            if(!wait_ready)begin wait_cycles<=wait_cycles-1'b1;if(wait_cycles==1)wait_ready<=1;end
            if(poll_timer!=0) poll_timer<=poll_timer-1'b1;
            if(state>=SETUP_START) begin
                if(frame_timer==FRAME_CYCLES-1) begin frame_timer<=0;frame_number<=frame_number+1'b1;sof_pending<=1;launch_window_q<=1;end
                else begin frame_timer<=frame_timer+1'b1;launch_window_q<=frame_timer<FRAME_CYCLES-FRAME_GUARD-1;end
            end else begin frame_timer<=0;frame_number<=0;sof_pending<=0;launch_window_q<=1;end
            if(state>=SETUP_START && line_state==0 && !oe) disconnect_timer<=disconnect_timer+1'b1;
            else disconnect_timer<=0;
            // 对下一计数值预判门限，切断计数器到所有控制寄存器的高扇出组合路径。
            disconnect_pending<=state>=SETUP_START&&line_state==0&&!oe&&disconnect_timer>=DISCONNECT_CYCLES-1;
            if(state>=SETUP_START && disconnect_pending) begin
                state<=DETACHED;connected<=0;fault<=1; // 拔出释放触摸，不动实体琴键。
            end else if(scheduler_state && sof_pending && !tr_busy) begin
                tr_mode<=3;tr_start<=1;sof_return<=state;state<=SOF_WAIT;sof_pending<=0;
            end else case(state)
                DETACHED: begin
                    connected<=0;step<=0;retries<=0;failures<=0;address<=0;endpoint<=0;wait_cycles<=0;wait_ready<=1;descriptor<=0;
                    if(line_state==2'b10) begin
                        if(timer==ATTACH_CYCLES-1) state<=BUS_RESET;
                    end
                end
                BUS_RESET: if(timer==RESET_CYCLES-1)state<=RECOVER;
                RECOVER: if(timer==RECOVERY_CYCLES-1)begin state<=SETUP_START;fault<=0;end
                SOF_WAIT: if(tr_done) state<=sof_return;
                SETUP_START: if(wait_ready && launch_window && transport_active) begin
                    tr_mode<=0;endpoint<=0;out_length<=8;out_toggle<=0;out_data<=setup_request(step);tr_start<=1;
                    state<=SETUP_WAIT;received<=0;control_toggle<=1;
                end
                SETUP_WAIT: if(tr_done) begin
                    if(result==0) begin retries<=0;state<=control_read?IN_START:STATUS_START;end
                    else if(retries<100) begin retries<=retries+1'b1;wait_cycles<=FRAME_CYCLES;wait_ready<=0;state<=SETUP_START;end
                    else begin state<=DETACHED;fault<=2;end
                end
                IN_START: if(wait_ready && launch_window) begin tr_mode<=1;endpoint<=0;tr_start<=1;state<=IN_WAIT;end
                IN_WAIT: if(tr_done) begin
                    if(result==0) begin
                        retries<=0;
                        if(in_toggle!=control_toggle) begin state<=IN_START;wait_cycles<=FRAME_CYCLES;wait_ready<=0;end
                        else if(in_length>64 || received+in_length>control_length) begin state<=DETACHED;fault<=3;end
                        else begin
                            // 设备/配置描述符都在单个64字节EP0包内；124字节报告描述符只计数。
                            if(store_descriptor && received==0) descriptor<=in_data[327:0];
                            received<=received+in_length;control_toggle<=~control_toggle;
                            if(in_length<64 || received+in_length==control_length) state<=STATUS_START;
                            else state<=IN_START;
                        end
                    end else if(retries<100) begin retries<=retries+1'b1;state<=IN_START;wait_cycles<=FRAME_CYCLES;wait_ready<=0;end
                    else begin state<=DETACHED;fault<=4;end
                end
                STATUS_START: if(wait_ready && launch_window) begin
                    tr_mode<=control_read?2:1;endpoint<=0;out_length<=0;out_data<=0;out_toggle<=1;tr_start<=1;state<=STATUS_WAIT;
                end
                STATUS_WAIT: if(tr_done) begin
                    if((result==0 && (control_read || (in_length==0 && in_toggle))) || (step==6 && result==2)) begin
                        retries<=0;state<=VALIDATE;
                    end else if(retries<100) begin retries<=retries+1'b1;state<=STATUS_START;wait_cycles<=FRAME_CYCLES;wait_ready<=0;end
                    else begin state<=DETACHED;fault<=5;end
                end
                VALIDATE: begin
                    if((step==0 && (received!=8 || descriptor[63:56]!=64 || descriptor[15:0]!=16'h0112)) ||
                       (step==2 && (received!=18 || !profile_device_q)) ||
                       (step==3 && (received!=41 || !profile_config_q)) || (step==5 && received!=124)) begin
                        state<=DETACHED;fault<=6; // 描述符不匹配，不向UI发布任何触点。
                    end else if(step==6) begin
                        connected<=1;poll_toggle<=0;poll_timer<=0;state<=POLL_IDLE;failures<=0;
                    end else begin
                        if(step==1) begin address<=1;wait_cycles<=2*FRAME_CYCLES;wait_ready<=0;end
                        step<=step+1'b1;state<=SETUP_START;descriptor<=0;
                    end
                end
                POLL_IDLE: if(poll_timer==0) state<=POLL_START;
                POLL_START: if(launch_window) begin tr_mode<=1;endpoint<=2;tr_start<=1;state<=POLL_WAIT;end
                POLL_WAIT: if(tr_done) begin
                    poll_timer<=POLL_CYCLES-1;state<=POLL_IDLE;
                    if(result==1) failures<=0; // 正常NAK表示设备在线，不释放持续音。
                    else if(result==0 && in_length==11) begin
                        failures<=0;
                        if(in_toggle==poll_toggle) begin report_data<=in_data[87:0];report_valid<=1;poll_toggle<=~poll_toggle;end
                    end else if(failures==7 || result==2) begin
                        connected<=0;state<=DETACHED;fault<=7;
                    end else failures<=failures+1'b1;
                end
                default: begin state<=DETACHED;connected<=0;end
            endcase
        end
    end
endmodule
