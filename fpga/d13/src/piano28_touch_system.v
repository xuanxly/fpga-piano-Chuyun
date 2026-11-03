`timescale 1ns/1ps
// 触摸协议与乐器逻辑之间的边界：仅接收完整、稳定且已映射到800x480的触点快照。
// frame_valid/active/ids/xs/ys必须与sys_clk同步，USB域应通过握手跨域后再提交。
module piano28_touch_system #(
    parameter integer BOOT_CYCLES=50000,ENABLE_USB_DIAG=0,ENABLE_MEDIA=0,
    parameter [279:0] PRESSURE_BASELINE={28{10'd0}},PRESSURE_FULL_SCALE={28{10'd1023}}
)(
    input wire ch_ready,ch_rx_req,ch_tx_ack,input wire [3:0] ch_rx_data,
    output wire ch_rx_ack,ch_tx_req,inout wire [3:0] ch_tx_data,
    input wire sys_clk,rst_n,enc_a,enc_b,dark_button_n,input wire [3:0] adc_miso,
    input wire touch_connected,touch_frame_valid,input wire [4:0] touch_active,
    input wire [39:0] touch_ids,input wire [49:0] touch_xs,touch_ys,
    output wire adc_cs_n,adc_sck,adc_mosi,output wire [9:0] transpose_led,output wire dark_led,
    output wire dac_bck,dac_ws,dac_din,pa_en,key_led_data,
    output wire i2s_bclk,i2s_lrclk,i2s_data,
    output wire tmds_clk_p,tmds_clk_n,output wire [2:0] tmds_data_p,tmds_data_n,output wire hpd_en,
    output wire [3:0] ui_page,output wire [6:0] ui_volume,output wire [27:0] monitor_keys,
    output wire monitor_valid,output wire signed [15:0] monitor_pcm,output wire [2:0] audio_fault,
    input wire [71:0] usb_diag,input wire [15:0] usb_runtime, // 只用于诊断显示，不接入演奏/音频路径。
    output wire sd_cs_n,sd_sck,sd_mosi,input wire sd_miso
);
    reg [31:0] boot_count=0;reg boot_done=0;
    always @(posedge sys_clk) if(!boot_done) begin
        if(boot_count==BOOT_CYCLES-1) boot_done<=1;else boot_count<=boot_count+1'b1;
    end
    wire effective_rst_n=rst_n & boot_done;
    wire sys_reset_n;
    reset_sync u_sys_reset(.clk(sys_clk),.ext_rst_n(effective_rst_n),.rst_n(sys_reset_n));
    wire [27:0] touch_keys;
    wire transpose_set_valid;wire signed [3:0] transpose_set; // 音调柱命令在50MHz域传入同一移调寄存器
    wire pixel_clk,serial_clk,locked,pixel_reset_n;
    wire [9:0] x,y;wire hs,vs,de,frame_tick;wire [2378:0] pixel_media;
    wire [2:0] timbre_selected; // 独立硬件选择，不依赖读卡/CPU响应
    wire [5:0] text_address;wire [31:0] text_data;
    wire media_nav_valid,media_command_valid,playback_exclusive,record_valid,sample_tick;
    wire [3:0] media_nav_page;wire [31:0] media_command,media_boot;wire [2175:0] media_status;
    wire signed [15:0] record_pcm,playback_l,playback_r;
    wire validation_run;wire [5:0] validation_count;wire [2:0] fx_enabled;wire [20:0] fx_levels;wire [191:0] verify_status;
    media_ui28 #(.ENABLE_EXTRA_APPS(ENABLE_MEDIA)) u_ui(.clk(sys_clk),.rst_n(sys_reset_n),.frame_valid(touch_frame_valid),.connected(touch_connected),
        .active(touch_active),.ids(touch_ids),.xs(touch_xs),.ys(touch_ys),.touch_keys(touch_keys),
        .volume_percent(ui_volume),.page(ui_page),.transpose_set_valid(transpose_set_valid),.transpose_set(transpose_set),
        .validation_run(validation_run),.validation_count(validation_count),.fx_enabled(fx_enabled),.fx_levels(fx_levels),.game_running(game_status[128]),.usb_exported(media_status[2071:2064]==17||media_status[2071:2064]==18),.nav_valid(media_nav_valid),.nav_page(media_nav_page),.command_valid(media_command_valid),.command(media_command),.timbre_selected(timbre_selected));
    wire [159:0] game_status;wire [4:0] effect_state;
    wire guide_active;wire [27:0] guide_keys,good_keys,bad_keys;
    wire dark;wire signed [3:0] transpose;
    piano28_core #(.ENABLE_TOUCH(1),.ENABLE_MEDIA(ENABLE_MEDIA),.ENABLE_TIMBRE(ENABLE_MEDIA),.ENABLE_EFFECTS(ENABLE_MEDIA),.ENABLE_NEW_APPS(ENABLE_MEDIA),.PRESSURE_BASELINE(PRESSURE_BASELINE),.PRESSURE_FULL_SCALE(PRESSURE_FULL_SCALE)) u_piano(
        .sys_clk(sys_clk),.rst_n(effective_rst_n),.adc_miso(adc_miso),.enc_a(enc_a),.enc_b(enc_b),.dark_button_n(dark_button_n),
        .adc_cs_n(adc_cs_n),.adc_sck(adc_sck),.adc_mosi(adc_mosi),.transpose_led(transpose_led),.dark_led(dark_led),
        .dac_bck(dac_bck),.dac_ws(dac_ws),.dac_din(dac_din),.pa_en(pa_en),
        .validation_page(ui_page==8),.validation_run(validation_run),.validation_count(validation_count),.fx_enabled(fx_enabled),.fx_levels(fx_levels),
        .i2s_bclk(i2s_bclk),.i2s_lrclk(i2s_lrclk),.i2s_data(i2s_data),.verify_status(verify_status),.touch_keys(touch_keys),.volume_percent(ui_volume),.timbre_select(timbre_selected),.transpose_set_valid(transpose_set_valid),.transpose_set(transpose_set),.monitor_valid(monitor_valid),.monitor_pcm(monitor_pcm),
        .monitor_keys(monitor_keys),.monitor_transpose(transpose),.monitor_dark(dark),.fault(audio_fault),
        .monitor_adc_valid(),.monitor_engine_done(),.monitor_engine_ready(),
        .playback_exclusive(playback_exclusive),.playback_l(playback_l),.playback_r(playback_r),
        .effect_state(effect_state),.record_valid(record_valid),.record_pcm(record_pcm),.monitor_sample_tick(sample_tick));
    generate if(ENABLE_MEDIA)begin:media
        media_soc u_media(.ch_ready(ch_ready),.ch_rx_req(ch_rx_req),.ch_tx_ack(ch_tx_ack),.ch_rx_data(ch_rx_data),.ch_rx_ack(ch_rx_ack),.ch_tx_req(ch_tx_req),.ch_tx_data(ch_tx_data),.keys(monitor_keys),.game_status(game_status),.guide_active(guide_active),.guide_keys(guide_keys),.good_keys(good_keys),.bad_keys(bad_keys),.clk(sys_clk),.rst_n(sys_reset_n),.page(ui_page),.command_valid(media_command_valid),.command(media_command),
            .record_valid(record_valid),.record_pcm(record_pcm),.sample_tick(sample_tick),.playback_exclusive(playback_exclusive),.play_l(playback_l),.play_r(playback_r),
            .pixel_clk(pixel_clk),.display_bank(pixel_media[0]),.text_address(text_address),.text_data(text_data),
            .ui_snapshot(media_status),.nav_valid(media_nav_valid),.nav_page(media_nav_page),.boot_status(media_boot),
            .sd_cs_n(sd_cs_n),.sd_sck(sd_sck),.sd_mosi(sd_mosi),.sd_miso(sd_miso));
    end else begin:no_media
        assign ch_rx_ack=0;assign ch_tx_req=0;assign ch_tx_data=4'bzzzz;assign game_status=0;assign guide_active=0;assign guide_keys=0;assign good_keys=0;assign bad_keys=0;
        assign text_data=32'h20202020;assign media_nav_valid=0;assign media_nav_page=0;assign media_status=0;assign media_boot=0;
        assign playback_exclusive=0;assign playback_l=0;assign playback_r=0;
        assign sd_cs_n=1;assign sd_sck=0;assign sd_mosi=1;
    end endgenerate
    piano28_lights #(.ENABLE_GAME(ENABLE_MEDIA)) u_lights(.guide_active(guide_active),.guide_keys(guide_keys),.good_keys(good_keys),.bad_keys(bad_keys),.clk(sys_clk),.rst_n(sys_reset_n),.key_gate(monitor_keys),.led_data(key_led_data));
    wire [255:0] levels;wire fft_valid,fft_overrun;
    // FFT读取主音量后的实际PCM；Home仅隐藏画面，不停止音频或采样。
    spectrum_fft u_fft(.clk(sys_clk),.rst_n(sys_reset_n),.pcm_valid(monitor_valid),.pcm(monitor_pcm),
        .frame_valid(fft_valid),.levels(levels),.overrun(fft_overrun),.bin_valid(),.bin_index(),.bin_real(),.bin_imag());
    spectrum_pll u_video_pll(.clkin(sys_clk),.clkout0(serial_clk),.clkout1(pixel_clk),.lock(locked));
    reset_sync u_pixel_reset(.clk(pixel_clk),.ext_rst_n(effective_rst_n & locked),.rst_n(pixel_reset_n));
    spectrum_timing u_timing(.clk(pixel_clk),.rst_n(pixel_reset_n),.x(x),.y(y),.hs(hs),.vs(vs),.de(de),.frame_tick(frame_tick));
    wire [298:0] snapshot;wire snapshot_valid;
    spectrum_cdc #(.WIDTH(299)) u_snapshot(.src_clk(sys_clk),.src_rst_n(sys_reset_n),
        .src_data({touch_connected,ui_volume,ui_page[1:0],dark,transpose,monitor_keys,levels}),
        .dst_clk(pixel_clk),.dst_rst_n(pixel_reset_n),.dst_frame(frame_tick),.dst_data(snapshot),.dst_valid(snapshot_valid));
    wire [23:0] rgb;wire video_hs,video_vs,video_de;
    wire [71:0] pixel_diag;
    spectrum_cdc #(.WIDTH(72)) u_diag_snapshot(.src_clk(sys_clk),.src_rst_n(sys_reset_n),
        .src_data(ENABLE_USB_DIAG ? usb_diag : 72'd0),.dst_clk(pixel_clk),.dst_rst_n(pixel_reset_n),
        .dst_frame(frame_tick),.dst_data(pixel_diag),.dst_valid());
    spectrum_cdc #(.WIDTH(2379)) u_media_snapshot(.src_clk(sys_clk),.src_rst_n(sys_reset_n),
        .src_data({game_status,effect_state,timbre_selected,media_boot,ui_page[2:0],media_status}),.dst_clk(pixel_clk),.dst_rst_n(pixel_reset_n),.dst_frame(frame_tick),.dst_data(pixel_media),.dst_valid());
    wire [255:0] pixel_extension;
    spectrum_cdc #(.WIDTH(256)) u_extension_snapshot(.src_clk(sys_clk),.src_rst_n(sys_reset_n),
        .src_data({12'd0,ui_page,usb_runtime,verify_status,fx_levels,fx_enabled,validation_count,validation_run,ui_page[3]}),
        .dst_clk(pixel_clk),.dst_rst_n(pixel_reset_n),.dst_frame(frame_tick),.dst_data(pixel_extension),.dst_valid());
    generate if(ENABLE_MEDIA)begin:media_video
        extended_ui_renderer #(.ENABLE_USB_DIAG(ENABLE_USB_DIAG)) u_renderer(.clk(pixel_clk),.rst_n(pixel_reset_n),.frame_tick(frame_tick),.snapshot_valid(snapshot_valid),
            .snapshot(snapshot),.extension(pixel_extension),.media_snapshot(pixel_media),.text_address(text_address),.text_data(text_data),.x(x),.y(y),.hs(hs),.vs(vs),.de(de),.hs_out(video_hs),.vs_out(video_vs),.de_out(video_de),.rgb(rgb),.usb_diag(pixel_diag));
    end else begin:legacy_video
        piano_ui_renderer #(.ENABLE_USB_DIAG(ENABLE_USB_DIAG)) u_renderer(.clk(pixel_clk),.rst_n(pixel_reset_n),.frame_tick(frame_tick),.snapshot_valid(snapshot_valid),
            .snapshot(snapshot),.x(x),.y(y),.hs(hs),.vs(vs),.de(de),.hs_out(video_hs),.vs_out(video_vs),.de_out(video_de),.rgb(rgb),.usb_diag(pixel_diag));
    end endgenerate
    spectrum_dvi u_dvi(.rst_n(pixel_reset_n),.serial_clk(serial_clk),.pixel_clk(pixel_clk),
        .hs(video_hs),.vs(video_vs),.de(video_de),.rgb(rgb),.clk_p(tmds_clk_p),.clk_n(tmds_clk_n),.data_p(tmds_data_p),.data_n(tmds_data_n));
    assign hpd_en=1'b1;
endmodule
