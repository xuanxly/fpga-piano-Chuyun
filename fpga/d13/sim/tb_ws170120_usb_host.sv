`timescale 1ns/1ps
module tb_ws170120_usb_host #(parameter integer BOARD=0,BAD_PROFILE=0,MANUAL_START=0,CLOCK_FAIL=0);
    reg clk=0;always #8.333333 clk=~clk;reg rst_n=0,attached=1;
    reg sys_clk=0;always #10 sys_clk=~sys_clk;
    reg dark_button_n=1;
    wire dp,dm,po,mo,oe,drive,pd,md;
    assign (weak1,weak0) dp=attached;assign (weak1,weak0) dm=1'b0;
    assign dp=drive?pd:1'bz;assign dm=drive?md:1'bz;
    wire connected,report_valid;wire [87:0] report_data;wire [3:0] fault;wire [7:0] state;
    usb_device_bfm dev(dp,dm,oe,drive,pd,md);
    wire fv;wire [4:0] active;wire [39:0] ids;wire [49:0] xs,ys;wire pe;
    wire [27:0] keys;wire [6:0] volume;wire [1:0] page;
    wire [3:0] step_monitor;integer pcm_nonzero=0,dac_frames=0;
    // 枚举等待在仿真中缩短；线上12Mbps、3ms轮询与1ms SOF保持真实时间。
    generate if(!BOARD) begin:g_host
        assign dp=oe?po:1'bz;assign dm=oe?mo:1'bz;
        ws170120_usb_host #(.ATTACH_CYCLES(1000),.RESET_CYCLES(1000),.RECOVERY_CYCLES(1000)) dut(
            clk,rst_n,dp,dm,po,mo,oe,connected,report_valid,report_data,fault,state);
        // 对照原组合定义逐拍检查预测标志，不允许重试等待或SOF窗口提前/延后一拍。
        always @(negedge clk)if(rst_n)begin
            if(dut.wait_ready!==(dut.wait_cycles==0))$fatal(1,"USB wait-ready prediction changed retry timing");
            if(dut.launch_window!==(dut.frame_timer<dut.FRAME_CYCLES-dut.FRAME_GUARD))$fatal(1,"USB launch-window prediction shifted frame guard");
        end
        assign step_monitor=dut.step;
        ws170120_reports decoder(clk,rst_n,connected,report_valid,7'd11,report_data,fv,active,ids,xs,ys,pe);
        touch_ui28 ui(.clk(clk),.rst_n(rst_n),.frame_valid(fv),.connected(connected),.active(active),.ids(ids),.xs(xs),.ys(ys),.touch_keys(keys),.volume_percent(volume),.page(page),.transpose_set_valid(),.transpose_set());
    end else begin:g_board
        wire bck,ws,din,pa;
        pressure_piano_28_touch_top #(.BOOT_CYCLES(100),.USB_ATTACH_CYCLES(1000),.USB_RESET_CYCLES(1000),.USB_RECOVERY_CYCLES(1000),
            .USB_AUTOSTART(MANUAL_START?0:1),.USB_ARM_CYCLES(50)) board(
            .sd_miso(1'b1),.sys_clk(sys_clk),.rst_n(rst_n),.enc_a(1'b1),.enc_b(1'b1),.dark_button_n(dark_button_n),.adc_miso(4'd0),
            .usb1_dp(1'b0),.usb1_dm(1'b0),.usb2_dp(dp),.usb2_dm(dm),.dac_bck(bck),.dac_ws(ws),.dac_din(din),.pa_en(pa)); // D6：USB1没有设备，全部枚举/报告必须从USB2进入。
        assign oe=board.usb_drive;assign connected=board.usb_connected;
        assign report_valid=board.report_valid;assign report_data=board.report_data;assign fault=board.usb_fault;assign state=board.usb_state;
        assign step_monitor=board.u_usb.step;assign active=board.usb_active;assign pe=board.report_error;
        assign keys=board.u_system.monitor_keys;assign volume=board.u_system.ui_volume;assign page=board.u_system.ui_page;
        initial if(MANUAL_START) begin
            wait(board.usb_healthy);#20000;
            if(board.usb_drive || connected) $fatal(1,"Manual mode enumerated before long press");
            dark_button_n=0;#2000;dark_button_n=1;
        end
        initial if(CLOCK_FAIL) begin
            wait(keys==31); // 已由真实USB引脚模型送达五指按下帧，再故障注入。
            force board.u_usb_pll.run_clock=0;
            #3000000;
            if(board.usb_drive || board.touch_connected || keys!=0 || !board.usb_watchdog_fault)
                $fatal(1,"Active five-finger touch stuck after USB clock loss");
            if(!board.u_system.sys_reset_n || dac_frames<1000 || pcm_nonzero<500)
                $fatal(1,"Clock fault interrupted independent piano system");
            $display("PASS touch_usb_clock_fault28: manual arm -> real-pin USB five-finger chord -> clock stops with LOCK high -> all touch gates released within 3ms, USB high-Z, system/DAC remain running");$finish;
        end
        reg [31:0] word=0;integer bit_index=0;reg signed [15:0] emitted;
        always @(negedge bck) if(board.u_system.u_piano.u_pt8211_tx.bit_index==0) emitted=board.u_system.u_piano.audio_sample;
        always @(posedge bck) if(board.u_system.sys_reset_n) begin
            word={word[30:0],din};
            if(ws!==(bit_index>=16)) $fatal(1,"USB board DAC channel");
            if(bit_index==31) begin
                if(word!=={emitted,emitted}) $fatal(1,"USB board stereo DAC data");
                bit_index=0;dac_frames++;
            end else bit_index++;
        end
        always @(posedge sys_clk) if(board.u_system.sys_reset_n) begin
            #1;if(board.u_system.audio_fault || board.u_system.fft_overrun || board.u_system.u_lights.render_overrun) $fatal(1,"USB board integration fault");
            if(board.usb_pin_seen[1:0]!==2'b00) $fatal(1,"Inactive USB1 monitor changed while USB2 was communicating");
            if(board.u_system.monitor_valid && board.u_system.monitor_pcm!=0) pcm_nonzero++;
        end
    end endgenerate
    reg [535:0] p,q;integer plen,qlen,kind=-1,sent=0,total=0,chunk=0,ep2=0;
    integer setup_count=0,sof_count=0,report_count=0,acks=0,last_sof=-1;realtime last_sof_time=0;
    reg [6:0] device_address=0;reg [63:0] setup;
    reg [991:0] contents=0;reg control_toggle=1,control_nak=0;
    reg [511:0] payload;integer endpoint,j;
    integer contact_index;
    function [87:0] touch_report(input integer idx,input tip,input integer stamp);
        reg [7:0] count,id;reg [15:0] x,y,t;begin
            count=(idx==0)?5:0;id=idx;x=20+96*idx;y=310;t=stamp;
            touch_report={count,t,y,x,8'd5,id,7'd0,tip,8'd1};
        end
    endfunction
    // 两个描述符是从实屏读取的数据；HID描述符本体以124字节占位，只测试多包传输。
    localparam [143:0] DEVICE=144'h01030201020000050eef4000000002000112;
    localparam [327:0] CONFIG=328'h0300400301050703004003820507007c2201000110210900000003020000040932c000010100290209;
    function [4:0] crc5(input [10:0] v);
        reg [4:0] c;integer n;begin
            c=31;for(n=0;n<11;n++) if(c[0]^v[n]) c=(c>>1)^5'h14;else c=c>>1;crc5=~c;
        end
    endfunction
    always @(posedge clk) begin #1;
        if(report_valid) begin
            report_count++;
            if(report_count==1 && report_data!==88'h0100640136001405000101) $fatal(1,"first USB touch payload");
            if(report_count==2 && report_data!==88'h0100650136001405000001) $fatal(1,"release USB touch payload");
            if(report_count>2 && report_count<=12) begin
                contact_index=(report_count-3)%5;
                if(report_data!==touch_report(contact_index,report_count<8,report_count<8?200:201)) $fatal(1,"USB chord report/toggle order");
            end
            if(report_count>12) $fatal(1,"duplicate USB DATA published");
        end
    end
    initial begin
        #201;rst_n=1;
        forever begin
            dev.receive_host(p,plen);
            case(p[7:0])
                8'ha5: begin
                    if(plen!=3 || p[23:19]!==crc5(p[18:8])) $fatal(1,"SOF CRC5");
                    if(last_sof>=0 && p[18:8]==last_sof) $fatal(1,"SOF frame number not advancing");
                    if(sof_count!=0 && ($realtime-last_sof_time<999500 || $realtime-last_sof_time>1000500)) $fatal(1,"SOF interval outside 1ms +/-0.5us: %f",$realtime-last_sof_time);
                    last_sof_time=$realtime;
                    last_sof=p[18:8];sof_count++;
                end
                8'h2d: begin
                    if(plen!=3 || p[14:8]!=device_address || p[18:15]!=0 || p[23:19]!==crc5(p[18:8])) $fatal(1,"SETUP token p=%h len=%d expected_addr=%d step=%d setup=%d",p[23:0],plen,device_address,step_monitor,setup_count);
                    dev.receive_host(q,qlen);
                    if(qlen!=11 || q[7:0]!=8'hc3 || q[87:72]!==dev.crc16(q[71:8],8)) $fatal(1,"SETUP DATA/CRC");
                    setup=q[71:8];setup_count++;sent=0;control_toggle=1;contents=0;
                    if(setup[15:8]==6) begin
                        total=setup[63:48];
                        case(setup[31:24])
                            1: begin contents=DEVICE;if(BAD_PROFILE==1) contents[95:80]=16'h0006;end
                            2: begin contents=CONFIG;if(BAD_PROFILE==2) contents[239:232]=8'h81;end
                            8'h22: begin for(j=0;j<124;j++) contents[j*8+:8]=j;end
                            default: $fatal(1,"unsupported descriptor request");
                        endcase
                    end else if(setup[15:8]==5 || setup[15:8]==9 || setup[15:8]==10) total=0;
                    else $fatal(1,"unexpected setup/boot command %h",setup);
                    dev.handshake(8'hd2);
                end
                8'h69: begin
                    if(plen!=3 || p[14:8]!=device_address || p[23:19]!==crc5(p[18:8])) $fatal(1,"IN token address/CRC");
                    endpoint=p[18:15];
                    if(endpoint==0) begin
                        if(!control_nak && total!=0) begin dev.handshake(8'h5a);control_nak=1;end
                        else if(total!=0) begin
                            chunk=total-sent;if(chunk>64) chunk=64;
                            payload=contents>>(sent*8);kind=0;dev.send_data(payload,chunk,control_toggle,0,83.333333333);
                        end else if(setup[15:8]==10) dev.handshake(8'h1e); // 可选SET_IDLE不支持。
                        else begin kind=1;dev.send_data(0,0,1,0,83.333333333);end
                    end else if(endpoint==2) begin
                        case(ep2)
                            0: begin kind=-1;dev.send_data(88'h0100640136001405000101,11,0,1,83.333333333);end
                            1: begin kind=2;dev.send_data(88'h0100640136001405000101,11,0,0,83.333333333);end
                            2: begin
                                if(keys!==1) $fatal(1,"touch note missing before duplicate");
                                kind=2;dev.send_data(88'h0100640136001405000101,11,0,0,83.333333333);
                            end
                            3: begin
                                if(keys!==1) $fatal(1,"NAK should keep held note");
                                dev.handshake(8'h5a);
                            end
                            default: begin
                                if(ep2==(BOARD?11:4)) begin
                                    if(keys!==1) $fatal(1,"NAK released held note");
                                    kind=2;dev.send_data(88'h0100650136001405000001,11,1,0,83.333333333);
                                end else if(ep2>(BOARD?11:4) && ep2<=(BOARD?21:14)) begin
                                    j=ep2-(BOARD?12:5); // 0..4五指按下，5..9五指抬起。
                                    if(j==5 && keys!==31) $fatal(1,"USB five-finger chord incomplete keys=%h",keys);
                                    kind=2;dev.send_data(touch_report(j%5,j<5,j<5?200:201),11,j%2,0,83.333333333);
                                end else dev.handshake(8'h5a);
                            end
                        endcase
                        ep2++;
                    end else $fatal(1,"host polled wrong endpoint %0d",endpoint);
                end
                8'he1: begin
                    if(p[14:8]!=device_address || p[18:15]!=0) $fatal(1,"OUT token");
                    dev.receive_host(q,qlen);
                    if(qlen!=3 || q[23:0]!=24'h00004b || sent!=total) $fatal(1,"read status ZLP");
                    dev.handshake(8'hd2);
                end
                8'hd2: begin
                    acks++;
                    if(kind==0) begin sent+=chunk;control_toggle=~control_toggle;end
                    if(kind==1 && setup[15:8]==5) device_address=1;
                    if(kind==-1) $fatal(1,"host ACKed corrupt data");kind=-1;
                end
                default: $fatal(1,"unexpected host PID %h",p[7:0]);
            endcase
        end
    end
    initial begin
        if(CLOCK_FAIL) wait(1'b0); // 此场景由上面的故障验证结束，而非等待抬指包。
        if(BAD_PROFILE!=0) begin
            wait(fault==6);#100;
            if(connected || report_count!=0 || keys!=0) $fatal(1,"unsupported device emitted touch");
            if(BAD_PROFILE==1) $display("PASS usb_reject_pid: unknown PID rejected before touch/configuration");
            else $display("PASS usb_reject_endpoint: wrong interrupt endpoint rejected before touch");
            $finish;
        end
        wait(connected);wait(ep2>=(BOARD?23:16));#100000;
        if(report_count!=12 || keys!=0 || pe || setup_count!=7 || sof_count<10) $fatal(1,"USB host coverage reps=%d keys=%h pe=%b setup=%d sof=%d",report_count,keys,pe,setup_count,sof_count);
        attached=0;#20000;if(connected || active || keys) $fatal(1,"USB detach did not release");
        if(BOARD) begin
            if(pcm_nonzero<500 || dac_frames<1000) $fatal(1,"USB to audio coverage PCM=%d DAC=%d",pcm_nonzero,dac_frames);
            if(MANUAL_START) $display("PASS touch_manual_usb_system28: passive/manual arm -> actual USB pins -> five-finger chord/release -> UI/audio/DAC, NAK hold/unplug; PCM_nonzero=%0d DAC=%0d",pcm_nonzero,dac_frames);
            else $display("PASS touch_usb_system28: actual USB pins -> host -> five-finger chord/release -> CDC -> UI -> piano -> scaled stereo DAC, sustained NAK and unplug; PCM_nonzero=%0d DAC=%0d",pcm_nonzero,dac_frames);
        end else $display("PASS ws170120_usb_host: actual device/config descriptors, EP0 two-packet report descriptor, optional STALL, 1ms SOF/CRC5, EP82, corrupt CRC not ACKed, duplicate DATA, five-finger chord, NAK hold, release and unplug; SOF=%0d ACK=%0d",sof_count,acks);
        $finish;
    end
    initial begin #100000000;$fatal(1,"host timeout state=%d step=%d fault=%d setup=%d ep2=%d",state,step_monitor,fault,setup_count,ep2);end
endmodule

module tb_touch_usb_system28;
    tb_ws170120_usb_host #(.BOARD(1)) test();
endmodule

module tb_touch_manual_usb_system28;
    tb_ws170120_usb_host #(.BOARD(1),.MANUAL_START(1)) test();
endmodule
module tb_touch_usb_clock_fault28;
    tb_ws170120_usb_host #(.BOARD(1),.MANUAL_START(1),.CLOCK_FAIL(1)) test();
endmodule

module tb_usb_reject_pid;
    tb_ws170120_usb_host #(.BAD_PROFILE(1)) test();
endmodule
module tb_usb_reject_endpoint;
    tb_ws170120_usb_host #(.BAD_PROFILE(2)) test();
endmodule
