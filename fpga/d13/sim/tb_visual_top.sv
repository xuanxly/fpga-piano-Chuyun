`timescale 1ns/1ps
module tb_visual_top;
    reg sys_clk=0;always #10 sys_clk=~sys_clk;
    reg rst_n=0;
    wire adc_cs_n,adc_sck,adc_mosi,adc_miso;
    wire [9:0] transpose_led; wire dark_led,dac_bck,dac_ws,dac_din,pa_en;
    wire tmds_clk_p,tmds_clk_n,hpd_en; wire [2:0] tmds_data_p,tmds_data_n;
    pressure_piano_visual_top top(.sys_clk(sys_clk),.rst_n(rst_n),.adc_miso(adc_miso),.enc_a(1'b1),.enc_b(1'b1),.dark_button_n(1'b1),
        .adc_cs_n(adc_cs_n),.adc_sck(adc_sck),.adc_mosi(adc_mosi),.transpose_led(transpose_led),.dark_led(dark_led),
        .dac_bck(dac_bck),.dac_ws(dac_ws),.dac_din(dac_din),.pa_en(pa_en),
        .tmds_clk_p(tmds_clk_p),.tmds_clk_n(tmds_clk_n),.tmds_data_p(tmds_data_p),.tmds_data_n(tmds_data_n),.hpd_en(hpd_en));
    reg [79:0] adc_values=0;
    wire integer transactions;
    mcp3008_model model(adc_cs_n,adc_sck,adc_mosi,adc_values,adc_miso,transactions);
    integer fft_frames=0,audio_frames=0,video_pixels=0,sounded=0,bit_index=0;
    reg [31:0] serial_word=0;
    reg signed [15:0] emitted_sample=0;
    always @(negedge dac_bck) if(rst_n && top.u_piano.u_pt8211_tx.bit_index==0) emitted_sample=top.u_piano.audio_sample;
    always @(posedge dac_bck) if(rst_n) begin
        serial_word={serial_word[30:0],dac_din};
        if(dac_ws !== (bit_index>=16)) $fatal(1,"visual top DAC WS");
        if(bit_index==31) begin
            if(serial_word !== {emitted_sample,emitted_sample}) $fatal(1,"visualization corrupted DAC PCM");
            audio_frames=audio_frames+1; bit_index=0;
            if(emitted_sample!=0) sounded=sounded+1;
        end else bit_index=bit_index+1;
    end
    always @(posedge sys_clk) if(rst_n) begin
        if(top.fft_overrun) $fatal(1,"integrated FFT overrun at real 48kHz sample rate");
        if(top.fft_valid) begin
            fft_frames=fft_frames+1;
            if(top.levels==0) $fatal(1,"sounding piano produced empty spectrum");
        end
    end
    always @(posedge top.pixel_clk) if(top.video_de) video_pixels=video_pixels+1;
    initial begin
        #201;rst_n=1;
        #2000000;adc_values[9:0]=700; adc_values[19:10]=600; adc_values[39:30]=800;
        #98000000;
        if(fft_frames<2 || audio_frames<4700 || sounded<4500 || video_pixels<2000000 || transactions<650)
            $fatal(1,"visual top coverage FFT=%0d PCM=%0d sounding=%0d pixels=%0d ADC=%0d",fft_frames,audio_frames,sounded,video_pixels,transactions);
        if(top.u_renderer.keys!=7'b0001011 || top.u_renderer.shown==0 || !hpd_en || pa_en) $fatal(1,"visual status snapshot");
        $display("PASS visual_top FFT_frames=%0d PCM_frames=%0d pixels=%0d ADC=%0d; behavioral PLL/DVI only",fft_frames,audio_frames,video_pixels,transactions);
        $finish;
    end
    initial begin #105000000;$fatal(1,"visual top timeout");end
endmodule
