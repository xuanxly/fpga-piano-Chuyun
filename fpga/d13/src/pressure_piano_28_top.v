`timescale 1ns/1ps
// 音频走NEO Dock J25耳机插座，HDMI仅输出画面。
module pressure_piano_28_top #(
    parameter integer BOOT_CYCLES=50000,         // 配置后自动复位1ms，不再依赖手动按下复位键
    parameter [279:0] PRESSURE_BASELINE={28{10'd0}}, // 每键松开时的实测ADC值，标定后填写
    parameter [279:0] PRESSURE_FULL_SCALE={28{10'd1023}} // 每键目标最大压力对应ADC值
) (
    input wire sys_clk, rst_n, enc_a, enc_b, dark_button_n,
    input wire [3:0] adc_miso,                    // 四块ADC独立DOUT，不可并接
    output wire adc_cs_n, adc_sck, adc_mosi,
    output wire [9:0] transpose_led, output wire dark_led,
    output wire dac_bck, dac_ws, dac_din, pa_en,
    output wire tmds_clk_p, tmds_clk_n,
    output wire [2:0] tmds_data_p, tmds_data_n,
    output wire hpd_en,                          // 底板 HDMI HPD 辅助使能，沿用官方连接
    output wire key_led_data                     // 新增灯板数据：J8-6 / AB20 → PCB4 U2-3
);
    // 配置初始化仅用于启动计数；外部复位仍可随时异步复位下游。
    reg [31:0] boot_count=0;
    reg boot_done=0;
    always @(posedge sys_clk) if(!boot_done) begin
        if(boot_count==BOOT_CYCLES-1) boot_done<=1;
        else boot_count<=boot_count+1'b1;
    end
    wire effective_rst_n=rst_n & boot_done;
    wire pcm_valid, dark,diag_adc,diag_done,diag_ready;
    wire signed [15:0] pcm;
    wire [27:0] keys;
    wire [2:0] audio_fault;
    wire signed [3:0] transpose;
    piano28_core #(.PRESSURE_BASELINE(PRESSURE_BASELINE),.PRESSURE_FULL_SCALE(PRESSURE_FULL_SCALE)) u_piano(
        .sys_clk(sys_clk),.rst_n(effective_rst_n),.adc_miso(adc_miso),.enc_a(enc_a),.enc_b(enc_b),
        .dark_button_n(dark_button_n),.adc_cs_n(adc_cs_n),.adc_sck(adc_sck),.adc_mosi(adc_mosi),
        .transpose_led(transpose_led),.dark_led(dark_led),.dac_bck(dac_bck),.dac_ws(dac_ws),
        .dac_din(dac_din),.pa_en(pa_en),.monitor_valid(pcm_valid),.monitor_pcm(pcm),
        .fault(audio_fault),.monitor_keys(keys),.monitor_transpose(transpose),.monitor_dark(dark),
        .monitor_adc_valid(diag_adc),.monitor_engine_done(diag_done),.monitor_engine_ready(diag_ready));
    wire sys_reset_n;
    reset_sync u_sys_reset(.clk(sys_clk),.ext_rst_n(effective_rst_n),.rst_n(sys_reset_n));
    piano28_lights u_lights(.clk(sys_clk),.rst_n(sys_reset_n),.key_gate(keys),.led_data(key_led_data));
    wire [255:0] levels;
    wire fft_valid, fft_overrun;
    spectrum_fft u_fft(.clk(sys_clk),.rst_n(sys_reset_n),.pcm_valid(pcm_valid),.pcm(pcm),
        .frame_valid(fft_valid),.levels(levels),.overrun(fft_overrun),
        .bin_valid(),.bin_index(),.bin_real(),.bin_imag());
    wire pixel_clk, serial_clk, locked, pixel_reset_n;
    spectrum_pll u_video_pll(.clkin(sys_clk),.clkout0(serial_clk),.clkout1(pixel_clk),.lock(locked));
    reset_sync u_pixel_reset(.clk(pixel_clk),.ext_rst_n(effective_rst_n & locked),.rst_n(pixel_reset_n));
    wire [9:0] x,y;
    wire hs,vs,de,frame_tick;
    spectrum_timing u_timing(.clk(pixel_clk),.rst_n(pixel_reset_n),.x(x),.y(y),
        .hs(hs),.vs(vs),.de(de),.frame_tick(frame_tick));
    wire [288:0] snapshot;                    // 256位频谱+28键+4位移调+明暗
    wire snapshot_valid;
    spectrum_cdc #(.WIDTH(289)) u_snapshot(.src_clk(sys_clk),.src_rst_n(sys_reset_n),
        .src_data({dark,transpose,keys,levels}),.dst_clk(pixel_clk),.dst_rst_n(pixel_reset_n),
        .dst_frame(frame_tick),.dst_data(snapshot),.dst_valid(snapshot_valid));
    wire [23:0] rgb;
    wire video_hs,video_vs,video_de;
    spectrum_renderer #(.KEY_COUNT(28)) u_renderer(.clk(pixel_clk),.rst_n(pixel_reset_n),.frame_tick(frame_tick),
        .snapshot_valid(snapshot_valid),.snapshot(snapshot),.x(x),.y(y),.hs(hs),.vs(vs),.de(de),
        .hs_out(video_hs),.vs_out(video_vs),.de_out(video_de),.rgb(rgb));
    wire [31:0] diagnostic,shown_diagnostic;
    audio_status28 u_audio_status(.clk(sys_clk),.rst_n(sys_reset_n),.adc_valid(diag_adc),.engine_done(diag_done),
        .engine_ready(diag_ready),.pcm_valid(pcm_valid),.fft_valid(fft_valid),.keys(keys),.pcm(pcm),
        .pa_en(pa_en),.fault(audio_fault),.status(diagnostic));
    spectrum_cdc #(.WIDTH(32)) u_diag_snapshot(.src_clk(sys_clk),.src_rst_n(sys_reset_n),.src_data(diagnostic),
        .dst_clk(pixel_clk),.dst_rst_n(pixel_reset_n),.dst_frame(frame_tick),.dst_data(shown_diagnostic),.dst_valid());
    reg [9:0] diag_x,diag_y;
    always @(posedge pixel_clk) begin diag_x<=x;diag_y<=y;end // 与renderer输出像素对齐
    reg [23:0] diag_rgb;
    integer marker,bit_no,bar_width;
    always @* begin
        diag_rgb=rgb;marker=0;bar_width=0;
        for(bit_no=0;bit_no<16;bit_no=bit_no+1) if(shown_diagnostic[8+bit_no]) bar_width=(bit_no+1)*16;
        if(video_de && diag_y>=36 && diag_y<46) begin
            if(diag_x>=16 && diag_x<112) begin
                marker=(diag_x-16)/12;
                if((diag_x-16)%12<9) diag_rgb=shown_diagnostic[marker] ? 24'h32d39a : 24'hb04040;
            end
            if(diag_x>=128 && diag_x<164) begin
                marker=(diag_x-128)/12;
                if((diag_x-128)%12<9) diag_rgb=shown_diagnostic[24+marker] ? 24'hff3030 : 24'h203040;
            end
            if(diag_x>=192 && diag_x<448) diag_rgb=(diag_x-192)<bar_width ? 24'h00bfff : 24'h18283a;
            if(diag_x>=760 && diag_x<784) diag_rgb=24'hffb020; // A28-R2版本识别：右上橙色块
        end
    end
    spectrum_dvi u_dvi(.rst_n(pixel_reset_n),.serial_clk(serial_clk),.pixel_clk(pixel_clk),
        .hs(video_hs),.vs(video_vs),.de(video_de),.rgb(diag_rgb),.clk_p(tmds_clk_p),.clk_n(tmds_clk_n),
        .data_p(tmds_data_p),.data_n(tmds_data_n));
    assign hpd_en=1'b1;
endmodule
