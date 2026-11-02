`timescale 1ns/1ps
module pressure_piano_top #(
    parameter integer CLK_HZ = 50000000,         // 官方示例为 50 MHz，仍须核对实物
    parameter integer ADC_SPI_HZ = 500000,       // MCP3008 单端采样 SPI 时钟
    parameter integer KEY_UPDATE_HZ = 1000,      // 七路各约 1 ms 更新一次
    parameter integer AMP_STARTUP_CYCLES = CLK_HZ / 50, // 复位后等待 20 ms 再开功放
    parameter [69:0] PRESSURE_BASELINE = {7{10'd0}},     // 空载值占位，CH0 在最低十位
    parameter [69:0] PRESSURE_FULL_SCALE = {7{10'd1023}} // 实物标定后替换七个最大值
)(
    input wire sys_clk,                         // 全工程统一系统时钟
    input wire rst_n,                           // 外部低有效复位
    input wire adc_miso,                        // ADC DOUT → FPGA
    output wire adc_cs_n,                       // FPGA → ADC CS
    output wire adc_sck,                        // FPGA → ADC CLK
    output wire adc_mosi,                       // FPGA → ADC DIN
    input wire enc_a, input wire enc_b,         // 编码器两相，外接上拉到 3.3 V
    input wire dark_button_n,                   // 明暗按钮，按下接地
    output wire [9:0] transpose_led,            // 左五灯降调，右五灯升调，原调全灭
    output wire dark_led,                       // 可选，偏暗时亮
    output wire dac_bck, output wire dac_ws, output wire dac_din, // PT8211 数字接口
    output reg pa_en,                           // NEO 31005 PA_EN：0 开功放，1 关功放
    output wire monitor_valid,                  // 同时刻送入 DAC 的 PCM 旁路，供频谱观察
    output wire signed [15:0] monitor_pcm,
    output wire [6:0] monitor_keys,
    output wire signed [3:0] monitor_transpose,
    output wire monitor_dark
);
    wire reset_n, sample_tick, raw_valid, dark_mode;
    wire [2:0] raw_channel;
    wire [9:0] raw_sample;                      // MCP3008 原始十位结果
    wire [6:0] key_gate;
    wire [83:0] key_pressure;                   // 持续音量运算用十二位
    wire signed [3:0] transpose;
    wire signed [15:0] audio_sample;
    wire [3:0] voice_active;                    // 按住和释放尾音都属于活动声部
    reg [31:0] amp_count;                       // 功放开启前的等待计数
    assign monitor_valid=sample_tick;            // 不反馈、不阻塞原有声音运算
    assign monitor_pcm=audio_sample;
    assign monitor_keys=key_gate;
    assign monitor_transpose=transpose;
    assign monitor_dark=dark_mode;

    reset_sync u_reset(.clk(sys_clk), .ext_rst_n(rst_n), .rst_n(reset_n)); // 异步复位，同步释放
    mcp3008_scan #(.CLK_HZ(CLK_HZ), .SPI_HZ(ADC_SPI_HZ), .KEY_UPDATE_HZ(KEY_UPDATE_HZ)) u_adc(
        .clk(sys_clk), .rst_n(reset_n), .adc_miso(adc_miso),
        .adc_cs_n(adc_cs_n), .adc_sck(adc_sck), .adc_mosi(adc_mosi),
        .raw_valid(raw_valid), .raw_channel(raw_channel), .raw_sample(raw_sample));
    pressure_frontend #(.BASELINE(PRESSURE_BASELINE), .FULL_SCALE(PRESSURE_FULL_SCALE)) u_pressure(
        .clk(sys_clk), .rst_n(reset_n), .raw_valid(raw_valid), .raw_channel(raw_channel),
        .raw_sample(raw_sample), .key_gate(key_gate), .key_pressure(key_pressure));
    instrument_controls #(.CLK_HZ(CLK_HZ)) u_controls(
        .clk(sys_clk), .rst_n(reset_n), .enc_a(enc_a), .enc_b(enc_b), .dark_button_n(dark_button_n),
        .transpose(transpose), .dark_mode(dark_mode), .transpose_led(transpose_led), .dark_led(dark_led),
        .transpose_set_valid(1'b0), .transpose_set(4'sd0)); // 七键旧入口不启用触摸移调
    piano_engine u_engine(.clk(sys_clk), .rst_n(reset_n), .sample_tick(sample_tick),
        .key_gate(key_gate), .key_pressure(key_pressure), .transpose(transpose), .dark_mode(dark_mode),
        .sample_out(audio_sample), .voice_active(voice_active)); // 只实例化四个实时合成声部
    pt8211_tx #(.CLK_HZ(CLK_HZ), .SAMPLE_HZ(48000)) u_pt8211_tx(
        .clk(sys_clk), .rst_n(reset_n), .sample_l(audio_sample), .sample_r(audio_sample), // 单声道混音复制到左右
        .sample_tick(sample_tick), .dac_bck(dac_bck), .dac_ws(dac_ws), .dac_din(dac_din));

    always @(posedge sys_clk or negedge reset_n) begin
        if (!reset_n) begin amp_count <= 0; pa_en <= 1; end // 复位时功放静音
        else if (amp_count < AMP_STARTUP_CYCLES) begin
            amp_count <= amp_count + 1'b1; pa_en <= 1;      // 先使 DAC 连续发送音频
        end else pa_en <= 0;                               // 打开底板功放，喇叭不接 GPIO
    end
endmodule
