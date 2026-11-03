`timescale 1ns/1ps
// 实板诊断：20ms统计一次真实数据流，不用“按键亮”代替音频产生证据。
module audio_status28 #(parameter integer WINDOW_CYCLES=1000000)(
    input wire clk,rst_n,adc_valid,engine_done,engine_ready,pcm_valid,fft_valid,
    input wire [27:0] keys,input wire signed [15:0] pcm,
    input wire pa_en,input wire [2:0] fault,output reg [31:0] status
);
    reg [31:0] count;
    reg seen_adc,seen_engine,seen_pcm,seen_fft;
    reg [15:0] peak;
    wire [15:0] magnitude=pcm[15] ? (~pcm+16'd1) : pcm;
    wire [15:0] next_peak=(pcm_valid && magnitude>peak) ? magnitude : peak;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin count<=0;seen_adc<=0;seen_engine<=0;seen_pcm<=0;seen_fft<=0;peak<=0;status<=0;end
        else begin
            if(adc_valid) seen_adc<=1;
            if(engine_done) seen_engine<=1;
            if(pcm_valid && pcm!=0) seen_pcm<=1;
            if(fft_valid) seen_fft<=1;
            peak<=next_peak;
            if(count==WINDOW_CYCLES-1) begin
                // 低8位从左往右：ADC、按键、引擎就绪、完成、非零PCM、功放启用、无故障、FFT。
                status<={5'd0,fault,next_peak,(seen_fft|fft_valid),~(|fault),~pa_en,
                         (seen_pcm|(pcm_valid && pcm!=0)),(seen_engine|engine_done),engine_ready,(|keys),(seen_adc|adc_valid)};
                count<=0;peak<=0;seen_adc<=0;seen_engine<=0;seen_pcm<=0;seen_fft<=0;
            end else count<=count+1'b1;
        end
    end
endmodule
