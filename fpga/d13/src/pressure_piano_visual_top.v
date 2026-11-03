`timescale 1ns/1ps
module pressure_piano_visual_top (
    input wire sys_clk, rst_n, adc_miso, enc_a, enc_b, dark_button_n,
    output wire adc_cs_n, adc_sck, adc_mosi,
    output wire [9:0] transpose_led, output wire dark_led,
    output wire dac_bck, dac_ws, dac_din, pa_en,
    output wire tmds_clk_p, tmds_clk_n,
    output wire [2:0] tmds_data_p, tmds_data_n,
    output wire hpd_en                           // 底板 HDMI HPD 辅助使能，沿用官方连接
);
    wire pcm_valid, dark;
    wire signed [15:0] pcm;
    wire [6:0] keys;
    wire signed [3:0] transpose;
    pressure_piano_top u_piano(
        .sys_clk(sys_clk),.rst_n(rst_n),.adc_miso(adc_miso),.enc_a(enc_a),.enc_b(enc_b),
        .dark_button_n(dark_button_n),.adc_cs_n(adc_cs_n),.adc_sck(adc_sck),.adc_mosi(adc_mosi),
        .transpose_led(transpose_led),.dark_led(dark_led),.dac_bck(dac_bck),.dac_ws(dac_ws),
        .dac_din(dac_din),.pa_en(pa_en),.monitor_valid(pcm_valid),.monitor_pcm(pcm),
        .monitor_keys(keys),.monitor_transpose(transpose),.monitor_dark(dark));
    wire sys_reset_n;
    reset_sync u_sys_reset(.clk(sys_clk),.ext_rst_n(rst_n),.rst_n(sys_reset_n));
    wire [255:0] levels;
    wire fft_valid, fft_overrun;
    spectrum_fft u_fft(.clk(sys_clk),.rst_n(sys_reset_n),.pcm_valid(pcm_valid),.pcm(pcm),
        .frame_valid(fft_valid),.levels(levels),.overrun(fft_overrun),
        .bin_valid(),.bin_index(),.bin_real(),.bin_imag());
    wire pixel_clk, serial_clk, locked, pixel_reset_n;
    spectrum_pll u_video_pll(.clkin(sys_clk),.clkout0(serial_clk),.clkout1(pixel_clk),.lock(locked));
    reset_sync u_pixel_reset(.clk(pixel_clk),.ext_rst_n(rst_n & locked),.rst_n(pixel_reset_n));
    wire [9:0] x,y;
    wire hs,vs,de,frame_tick;
    spectrum_timing u_timing(.clk(pixel_clk),.rst_n(pixel_reset_n),.x(x),.y(y),
        .hs(hs),.vs(vs),.de(de),.frame_tick(frame_tick));
    wire [267:0] snapshot;
    wire snapshot_valid;
    spectrum_cdc u_snapshot(.src_clk(sys_clk),.src_rst_n(sys_reset_n),
        .src_data({dark,transpose,keys,levels}),.dst_clk(pixel_clk),.dst_rst_n(pixel_reset_n),
        .dst_frame(frame_tick),.dst_data(snapshot),.dst_valid(snapshot_valid));
    wire [23:0] rgb;
    wire video_hs,video_vs,video_de;
    spectrum_renderer u_renderer(.clk(pixel_clk),.rst_n(pixel_reset_n),.frame_tick(frame_tick),
        .snapshot_valid(snapshot_valid),.snapshot(snapshot),.x(x),.y(y),.hs(hs),.vs(vs),.de(de),
        .hs_out(video_hs),.vs_out(video_vs),.de_out(video_de),.rgb(rgb));
    spectrum_dvi u_dvi(.rst_n(pixel_reset_n),.serial_clk(serial_clk),.pixel_clk(pixel_clk),
        .hs(video_hs),.vs(video_vs),.de(video_de),.rgb(rgb),.clk_p(tmds_clk_p),.clk_n(tmds_clk_n),
        .data_p(tmds_data_p),.data_n(tmds_data_n));
    assign hpd_en=1'b1;
endmodule
