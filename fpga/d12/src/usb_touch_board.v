`timescale 1ns/1ps
// D8双柱界面，沿用D7已实板触摸正常的USB输出级：USB2使能改为INIT=1的直接寄存器输出；尚待实板验证。
// USBA-Switch必须朝FPGA；耳机J25、HDMI、37个原有功能球位均保持。
module pressure_piano_28_touch_top #(
    parameter integer BOOT_CYCLES=50000,
    parameter integer USB_ATTACH_CYCLES=6000000,USB_RESET_CYCLES=1200000,USB_RECOVERY_CYCLES=600000,
    parameter integer USB_ARM_CYCLES=100000000,USB_WATCHDOG_CYCLES=100000,USB_AUTOSTART=0
)(
    input wire ch_ready,ch_rx_req,ch_tx_ack,input wire [3:0] ch_rx_data,
    output wire ch_rx_ack,ch_tx_req,inout wire [3:0] ch_tx_data,
    input wire sys_clk,rst_n,enc_a,enc_b,dark_button_n,input wire [3:0] adc_miso,
    output wire adc_cs_n,adc_sck,adc_mosi,output wire [9:0] transpose_led,output wire dark_led,
    output wire dac_bck,dac_ws,dac_din,pa_en,key_led_data,
    output wire tmds_clk_p,tmds_clk_n,output wire [2:0] tmds_data_p,tmds_data_n,output wire hpd_en,
    input wire usb1_dp,usb1_dm,      // 原USB1只读观察，编译后必须为input。
    inout wire usb2_dp,usb2_dm,      // D5实板读到Full-Speed J电平的线路。
    output wire sd_cs_n,sd_sck,sd_mosi,input wire sd_miso // 卡槽四线SPI；上拉由CST指定，避免推导出第二个驱动。
);
    reg [31:0] boot_count=0;reg boot_done=0;
    always @(posedge sys_clk) if(!boot_done) begin
        if(boot_count==BOOT_CYCLES-1) boot_done<=1;else boot_count<=boot_count+1'b1;
    end
    wire effective_rst_n=rst_n & boot_done;
    wire usb_clk,usb_lock,usb_rst_n,sys_rst_n;
    usb_pll60 u_usb_pll(.clkin(sys_clk),.clkout0(usb_clk),.clkout1(),.lock(usb_lock));
    reset_sync u_usb_reset(.clk(usb_clk),.ext_rst_n(effective_rst_n & usb_lock),.rst_n(usb_rst_n));
    reset_sync u_ui_reset(.clk(sys_clk),.ext_rst_n(effective_rst_n),.rst_n(sys_rst_n));
    wire dp_o,dm_o,usb_oe,usb_connected,report_valid;wire [87:0] report_data;
    wire [3:0] usb_fault;wire [7:0] usb_state;
    wire [63:0] usb_info;wire [71:0] usb_diagnostic,usb_diagnostic_base;
    reg [6:0] usb_heartbeat_count;
    always @(posedge usb_clk or negedge usb_rst_n) begin
        if(!usb_rst_n) usb_heartbeat_count<=0;else usb_heartbeat_count<=usb_heartbeat_count+1'b1;
    end
    wire usb_armed,usb_healthy,usb_watchdog_fault,host_rst_n;
    usb_session_guard #(.ARM_CYCLES(USB_ARM_CYCLES),.WATCHDOG_CYCLES(USB_WATCHDOG_CYCLES),.AUTOSTART(USB_AUTOSTART)) u_guard(
        .clk(sys_clk),.rst_n(sys_rst_n),.button_n(dark_button_n),.usb_lock(usb_lock),.usb_heartbeat(usb_heartbeat_count[6]),
        .armed(usb_armed),.healthy(usb_healthy),.watchdog_fault(usb_watchdog_fault));
    wire session_allowed=usb_armed && usb_healthy && !usb_watchdog_fault;
    reset_sync u_host_reset(.clk(usb_clk),.ext_rst_n(usb_rst_n && session_allowed),.rst_n(host_rst_n));
    // allow由两级60MHz会话复位同步释放；撤销会话/掉锁时异步关断，不等待USB时钟。
    wire usb_pad_allow=session_allowed && usb_lock && host_rst_n;
    wire usb_drive;
    wire usb2_dp_rx,usb2_dm_rx;
    usb_pad_pair_registered u_usb2_pads(.clk(usb_clk),.allow(usb_pad_allow),.tx_enable(usb_oe),
        .dp_tx(dp_o),.dm_tx(dm_o),.dp(usb2_dp),.dm(usb2_dm),
        .dp_rx(usb2_dp_rx),.dm_rx(usb2_dm_rx),.drive(usb_drive));
    (* ASYNC_REG="TRUE",syn_preserve=1 *) reg [2:0] usb_pin_meta,usb_pin_seen;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin usb_pin_meta<=0;usb_pin_seen<=0;end
        else begin usb_pin_meta<={usb_drive,usb1_dm,usb1_dp};usb_pin_seen<=usb_pin_meta;end
    end
    (* ASYNC_REG="TRUE",syn_preserve=1 *) reg [1:0] usb2_meta,usb2_seen;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin usb2_meta<=0;usb2_seen<=0;end
        else begin usb2_meta<={usb2_dp_rx,usb2_dm_rx};usb2_seen<=usb2_meta;end
    end
    // D/P/M/O来自50MHz的独立同步采样，USB主机尚未启动也可以读出线路电平。
    // Dxx=USB1，U2xx=USB2物理电平；O=主机当前USB2驱动允许，保持72位邮箱。
    assign usb_diagnostic={usb_pin_seen[2:0],usb_armed,usb_diagnostic_base[67:14],usb2_seen,usb_diagnostic_base[11:0]};
    ws170120_usb_host #(.ATTACH_CYCLES(USB_ATTACH_CYCLES),.RESET_CYCLES(USB_RESET_CYCLES),.RECOVERY_CYCLES(USB_RECOVERY_CYCLES)) u_usb(
        usb_clk,host_rst_n,usb2_dp_rx,usb2_dm_rx,dp_o,dm_o,usb_oe,usb_connected,report_valid,report_data,usb_fault,usb_state,usb_info);
    wire usb_frame_valid;wire [4:0] usb_active;wire [39:0] usb_ids;wire [49:0] usb_xs,usb_ys;wire report_error;
    ws170120_reports u_reports(usb_clk,host_rst_n,usb_connected,report_valid,7'd11,report_data,
        usb_frame_valid,usb_active,usb_ids,usb_xs,usb_ys,report_error);
    wire touch_connected,touch_valid,touch_connected_raw,touch_valid_raw;
    wire [4:0] touch_active;wire [39:0] touch_ids;wire [49:0] touch_xs,touch_ys;
    touch_frame_cdc u_touch_cdc(usb_clk,usb_rst_n,usb_connected,usb_frame_valid,usb_active,usb_ids,usb_xs,usb_ys,
        sys_clk,sys_rst_n,touch_connected_raw,touch_valid_raw,touch_active,touch_ids,touch_xs,touch_ys);
    // USB时钟停止时跨域邮箱不会再更新，因此50MHz侧必须主动释放触摸，避免音符卡住。
    assign touch_connected=touch_connected_raw && session_allowed;
    assign touch_valid=touch_valid_raw && session_allowed;
    usb_diag_bridge u_usb_diag(.usb_clk(usb_clk),.usb_rst_n(usb_rst_n),.usb_info(usb_info),
        .usb_lock(usb_lock),.report_error(report_error),.sys_clk(sys_clk),.sys_rst_n(sys_rst_n),.diagnostic(usb_diagnostic_base));
    piano28_touch_system #(.BOOT_CYCLES(1),.ENABLE_USB_DIAG(1),.ENABLE_MEDIA(1)) u_system(.ch_ready(ch_ready),.ch_rx_req(ch_rx_req),.ch_tx_ack(ch_tx_ack),.ch_rx_data(ch_rx_data),.ch_rx_ack(ch_rx_ack),.ch_tx_req(ch_tx_req),.ch_tx_data(ch_tx_data),
        .sys_clk(sys_clk),.rst_n(effective_rst_n),.enc_a(enc_a),.enc_b(enc_b),.dark_button_n(dark_button_n),.adc_miso(adc_miso),
        .touch_connected(touch_connected),.touch_frame_valid(touch_valid),.touch_active(touch_active),
        .touch_ids(touch_ids),.touch_xs(touch_xs),.touch_ys(touch_ys),
        .adc_cs_n(adc_cs_n),.adc_sck(adc_sck),.adc_mosi(adc_mosi),.transpose_led(transpose_led),.dark_led(dark_led),
        .dac_bck(dac_bck),.dac_ws(dac_ws),.dac_din(dac_din),.pa_en(pa_en),.key_led_data(key_led_data),
        .tmds_clk_p(tmds_clk_p),.tmds_clk_n(tmds_clk_n),.tmds_data_p(tmds_data_p),.tmds_data_n(tmds_data_n),.hpd_en(hpd_en),
        .ui_page(),.ui_volume(),.monitor_keys(),.monitor_valid(),.monitor_pcm(),.audio_fault(),.usb_diag(usb_diagnostic),
        .sd_cs_n(sd_cs_n),.sd_sck(sd_sck),.sd_mosi(sd_mosi),.sd_miso(sd_miso));
endmodule

`ifdef PIANO_XSIM
// 行为模型只检查数字链路，实际PLL/USB电气必须在板上确认。
module usb_pll60(input wire clkin,output reg clkout0=0,output wire clkout1,output reg lock=0);
    reg run_clock=1; // 仿真故障注入：可停时钟但保持LOCK，验证独立看门狗。
    always #8.333333333 if(run_clock) clkout0=~clkout0;
    assign clkout1=1'b0;
    initial begin #200;lock=1;end
endmodule
`endif
