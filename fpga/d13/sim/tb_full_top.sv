`timescale 1ns/1ps
module tb_full_top;
    reg clk=0;always #10 clk=~clk; // 整机使用真实 50 MHz 时钟及真实 48 kHz DAC 节拍
    reg rst_n=0,enc_a=1,enc_b=1,button_n=1;
    reg [79:0] adc_values=0; // 八路十位输入，首版扫描 CH0～CH6
    wire cs_n,sck,mosi,miso,bck,ws,din,dark_led,pa_en;
    wire [9:0] leds;wire integer transactions;
    pressure_piano_top top(.sys_clk(clk),.rst_n(rst_n),.adc_miso(miso),
        .adc_cs_n(cs_n),.adc_sck(sck),.adc_mosi(mosi),.enc_a(enc_a),.enc_b(enc_b),
        .dark_button_n(button_n),.transpose_led(leds),.dark_led(dark_led),
        .dac_bck(bck),.dac_ws(ws),.dac_din(din),.pa_en(pa_en));
    mcp3008_model model(cs_n,sck,mosi,adc_values,miso,transactions);
    integer frames=0,bits_seen=0,nonzero_frames=0,raw_count=0,expected_channel=0;
    reg [31:0] received=0;
    reg signed [15:0] captured_sample=0;
    time first_audio_time=0,press_time=0,last_raw_time[0:6];
    always @(negedge bck) if(rst_n && top.u_pt8211_tx.bit_index==0)
        captured_sample=top.audio_sample; // 发帧边沿原子锁定左右声道输入
    always @(posedge bck) if(rst_n) begin
        if(ws !== (bits_seen>=16)) $fatal(1,"PT8211 right/left WS polarity");
        received={received[30:0],din};
        if(bits_seen==31) begin
            if(received !== {captured_sample,captured_sample}) $fatal(1,"PCM to PT8211 serial data mismatch");
            frames=frames+1;bits_seen=0;
            if(received!=0) begin
                nonzero_frames=nonzero_frames+1;
                if(first_audio_time==0) first_audio_time=$time;
            end
        end else bits_seen=bits_seen+1;
    end
    always @(posedge clk) begin
        if(top.raw_valid) begin
            if(top.raw_channel!=expected_channel) $fatal(1,"ADC polling channel order");
            if(top.raw_sample !== model.value) $fatal(1,"ADC returned 10-bit sample mismatch");
            if(last_raw_time[expected_channel]!=0 && ($time-last_raw_time[expected_channel]<999000 || $time-last_raw_time[expected_channel]>1001000))
                $fatal(1,"per-key update interval is not 1 ms");
            last_raw_time[expected_channel]=$time;
            if(expected_channel==6) expected_channel=0;else expected_channel=expected_channel+1;
            raw_count=raw_count+1;
        end
    end
    initial begin
        for(integer i=0;i<7;i=i+1) last_raw_time[i]=0;
        #101;rst_n=1;
        #19000000;
        if(!pa_en) $fatal(1,"amplifier enabled before startup wait");
        #2000000;
        if(pa_en) $fatal(1,"amplifier did not enable after 20 ms");
        #500000;press_time=$time;
        adc_values[9:0]=400;adc_values[19:10]=550;adc_values[29:20]=700;adc_values[39:30]=850;
        #3500000;
        if(top.voice_active!=15 || nonzero_frames<50) $fatal(1,"integrated four-key chord did not sound");
        if(first_audio_time==0 || first_audio_time-press_time>10000000) $fatal(1,"simulated trigger to audio exceeds 10 ms");
        button_n=0;
        {enc_a,enc_b}=2'b10;#1200000;{enc_a,enc_b}=2'b00;#1200000; // 两次转换正好一个定位格
        if(top.transpose!=1 || leds!=10'b0000100000) $fatal(1,"integrated encoder transpose");
        adc_values[9:0]=125;
        #5000000;
        if(!dark_led || top.u_engine.u_tone.blend!=256) $fatal(1,"integrated dark mode");
        if(top.u_engine.g_voice[0].u_voice.pressure_gain>=top.u_engine.g_voice[1].u_voice.pressure_gain)
            $fatal(1,"integrated independent pressure gain");
        adc_values=0;#15000000; // 1/4 滤波从大压力降至松开门限约需 13 轮，留足等待时间
        if(top.key_gate!=0) $fatal(1,"all physical key gates must release after filtering");
        if(top.u_engine.g_voice[1].u_voice.state!=3'd4) $fatal(1,"release tail must remain in envelope release state");
        if(frames<600 || raw_count<90 || transactions<90) $fatal(1,"not enough real-clock integration coverage");
        wait(cs_n);@(negedge clk);rst_n=0;#100;
        if(!pa_en) $fatal(1,"reset must mute amplifier immediately");
        $display("PASS full_top frames=%0d nonzero=%0d adc=%0d simulated_onset_ns=%0d",frames,nonzero_frames,raw_count,first_audio_time-press_time); // %d 按本模块 ns 单位输出，避免 %t 自动显示 ps
        $finish;
    end
    initial begin #60000000;$fatal(1,"full top timeout");end // 仿真挂住时给出明确失败
endmodule
