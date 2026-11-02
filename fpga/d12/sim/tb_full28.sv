`timescale 1ns/1ps
module tb_full28 #(parameter COLD_START=0);
    reg sys_clk=0;always #10 sys_clk=~sys_clk;reg rst_n=COLD_START ? 1 : 0;
    wire cs,sck,mosi;wire [3:0] miso;wire [9:0] leds;wire dark_led,bck,ws,din,pa;
    wire cp,cn,hpd;wire [2:0] dp,dn;
    wire key_led_data;
    pressure_piano_28_top top(sys_clk,rst_n,1'b1,1'b1,1'b1,miso,cs,sck,mosi,leds,dark_led,bck,ws,din,pa,cp,cn,dp,dn,hpd,key_led_data);
    reg [79:0] values[0:3];wire integer transactions[0:3];
    genvar b;generate for(b=0;b<4;b=b+1) begin:model
        mcp3008_model m(cs,sck,mosi,values[b],miso[b],transactions[b]);
    end endgenerate
    integer fft_frames=0,audio_frames=0,sounding=0,engine_frames=0,pixels=0,bit_index=0,k,j;
    reg [31:0] serial_word=0;reg signed [15:0] emitted=0;
    reg [27:0] seen_active=0;integer gap=0;reg accepted_tick;
    reg [23:0] light_expected[0:1007];             // 独立Python生成：首帧全黑，之后28键全部按住
    integer light_frames=0;
    initial begin:decode_lighting
        integer n,b;time t;reg [23:0] word;
        $readmemh("light_allheld.hex",light_expected);
        wait(rst_n);
        forever begin
            @(posedge key_led_data);
            if(light_frames>=9) $fatal(1,"Unexpected lighting frame count");
            for(n=0;n<112;n=n+1) begin
                word=0;
                for(b=23;b>=0;b=b-1) begin
                    t=$time;@(negedge key_led_data);
                    if($time-t!=320 && $time-t!=640) $fatal(1,"Integrated WS2812 pulse width");
                    word={word[22:0],($time-t==640)};
                    if(n!=111 || b!=0) @(posedge key_led_data);
                end
                if(word!==light_expected[light_frames*112+n])
                    $fatal(1,"Integrated LED mismatch frame=%0d D%03d got=%h expected=%h",light_frames,n+1,word,light_expected[light_frames*112+n]);
            end
            light_frames=light_frames+1;
        end
    end
    always @(negedge bck) if(rst_n && top.u_piano.u_pt8211_tx.bit_index==0) emitted=top.u_piano.audio_sample;
    always @(posedge bck) if(rst_n) begin
        serial_word={serial_word[30:0],din};
        if(ws!==(bit_index>=16)) $fatal(1,"28 top DAC channel framing");
        if(bit_index==31) begin
            if(serial_word!=={emitted,emitted}) $fatal(1,"28 top DAC payload differs from filtered PCM");
            if($signed(emitted)>16384 || $signed(emitted)<-16384) $fatal(1,"28 top earphone peak");
            audio_frames=audio_frames+1;if(emitted!=0) sounding=sounding+1;bit_index=0;
        end else bit_index=bit_index+1;
    end
    always @(posedge sys_clk) if(rst_n) begin
        accepted_tick=top.u_piano.sample_tick; // 先取引擎本拍读到的节拍，再观察寄存器更新后的done
        #1;
        if(top.audio_fault || top.fft_overrun || top.u_lights.render_overrun) $fatal(1,"28 top fault ADC/pressure/deadline/FFT/lighting");
        seen_active=seen_active|top.u_piano.voice_active;
        if(accepted_tick) gap=0;else gap=gap+1;
        if(top.u_piano.engine_done) begin if(gap!=896) $fatal(1,"engine integration latency=%0d",gap);engine_frames=engine_frames+1;end
        if(top.fft_valid) begin fft_frames=fft_frames+1;if(top.levels==0) $fatal(1,"28 top empty spectrum");end
    end
    always @(posedge top.pixel_clk) if(top.video_de) pixels=pixels+1;
    initial begin
        for(j=0;j<4;j=j+1) values[j]=0;
        #201;rst_n=1;#2000000;
        for(j=0;j<4;j=j+1) for(k=0;k<7;k=k+1) values[j][k*10+:10]=400+j*120+k*20;
        #98000000;
        if(fft_frames<2 || audio_frames<4700 || engine_frames<4700 || sounding<4500 || pixels<2000000 || seen_active!==28'hfffffff)
            $fatal(1,"28 top insufficient coverage fft=%0d audio=%0d engine=%0d sound=%0d pixels=%0d keys=%h",fft_frames,audio_frames,engine_frames,sounding,pixels,seen_active);
        for(j=0;j<4;j=j+1) if(transactions[j]<650) $fatal(1,"28 top ADC traffic");
        if(top.u_renderer.keys!==28'hfffffff || top.u_renderer.shown==0 || !hpd || pa) $fatal(1,"28 top snapshot/startup PA");
        if(light_frames<6) $fatal(1,"Integrated lighting did not complete six 112-LED frames");
        // 四块ADC值不同，同一通道的压力必须分别保持。
        for(j=1;j<4;j=j+1) if(top.u_piano.key_pressure[j*84+:12]===top.u_piano.key_pressure[0+:12]) $fatal(1,"ADC bank pressures aliased");
        $display("PASS full28: FFT=%0d PCM=%0d engine=%0d pixels=%0d LEDframes=%0d, all28 sounding, exact stereo DAC and 112-LED GRB, separate ADC banks; behavioral PLL/DVI only",fft_frames,audio_frames,engine_frames,pixels,light_frames);$finish;
    end
    initial begin #105000000;$fatal(1,"28 full timeout");end
endmodule
module tb_cold_start28;
    tb_full28 #(.COLD_START(1)) cold();
endmodule
