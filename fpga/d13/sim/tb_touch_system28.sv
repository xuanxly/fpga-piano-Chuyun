`timescale 1ns/1ps
module tb_touch_system28;
    reg sys_clk=0;always #10 sys_clk=~sys_clk;reg rst_n=0;
    reg connected=1,valid=0;reg [4:0] active=0;reg [39:0] ids=0;reg [49:0] xs=0,ys=0;
    wire cs,sck,mosi;wire [3:0] miso;wire [27:0] keys;wire [1:0] page;
    wire [6:0] volume;wire pv,pa;wire signed [15:0] pcm;wire [2:0] fault;
    wire bck,ws,din;
    piano28_touch_system #(.BOOT_CYCLES(10)) dut(.sys_clk(sys_clk),.rst_n(rst_n),.enc_a(1'b1),.enc_b(1'b1),.dark_button_n(1'b1),
        .adc_miso(miso),.touch_connected(connected),.touch_frame_valid(valid),.touch_active(active),.touch_ids(ids),.touch_xs(xs),.touch_ys(ys),
        .adc_cs_n(cs),.adc_sck(sck),.adc_mosi(mosi),.pa_en(pa),.ui_page(page),.ui_volume(volume),
        .monitor_keys(keys),.monitor_valid(pv),.monitor_pcm(pcm),.audio_fault(fault),.dac_bck(bck),.dac_ws(ws),.dac_din(din));
    reg [79:0] values[0:3];wire integer transactions[0:3];
    genvar b;generate for(b=0;b<4;b++) begin:models
        mcp3008_model m(cs,sck,mosi,values[b],miso[b],transactions[b]);
    end endgenerate
    task send;begin @(negedge sys_clk);valid=1;@(negedge sys_clk);valid=0;end endtask
    task clear;begin active=0;send();end endtask
    task press(input integer slot,id,x,y);begin active[slot]=1;ids[slot*8+:8]=id;xs[slot*10+:10]=x;ys[slot*10+:10]=y;end endtask
    task tap(input integer x,y);begin clear();press(0,1,x,y);send();clear();end endtask
    integer phase=0,nz[0:3],i,mag,pcm_count=0,fft_count=0;
    reg [31:0] word=0;integer bit_index=0;reg signed [15:0] emitted;
    // 从实际DAC输出逐位核对，确保主音量真正作用于耳机路径。
    always @(negedge bck) if(dut.u_piano.u_pt8211_tx.bit_index==0) emitted=dut.u_piano.audio_sample;
    always @(posedge bck) if(dut.sys_reset_n) begin
        word={word[30:0],din};
        if(ws!==(bit_index>=16)) $fatal(1,"touch DAC channel");
        if(bit_index==31) begin
            if(word!=={emitted,emitted}) $fatal(1,"DAC did not emit scaled PCM");
            bit_index=0;
        end else bit_index++;
    end
    always @(posedge sys_clk) if(dut.sys_reset_n) begin
        #1;if(fault || dut.fft_overrun || dut.u_lights.render_overrun) $fatal(1,"integration fault");
        if(pv) begin
            pcm_count++;mag=$signed(pcm);if(mag<0) mag=-mag;
            if(mag!=0) nz[phase]++;
            if(mag>16384) $fatal(1,"output ceiling");
        end
        if(dut.fft_valid) fft_count++;
    end
    initial begin
        for(i=0;i<4;i++) begin values[i]=0;nz[i]=0;end
        #201;rst_n=1;#2000000;
        // 等过20ms功放启动静音窗口，再验收发声和功放使能。
        press(0,10,20,310);press(1,11,116,310);send();#20000000;
        if(keys!=3 || nz[0]<500 || pa) $fatal(1,"touch chord no audio keys=%h PCM=%d PA=%b",keys,nz[0],pa);
        values[3][69:60]=700;#3000000;
        tap(740,450);phase=1;#18000000;
        if(page!=0 || keys!==28'h8000000 || nz[1]<500) $fatal(1,"Home lost physical pad");
        press(0,20,728,400);send();clear();#7000000;phase=2;#6000000;
        if(volume!=0 || pcm!=0 || nz[2]!=0) $fatal(1,"Home mute not applied");
        press(0,21,728,64);send();clear();tap(500,200);phase=3;
        press(0,30,20,98);press(1,31,116,98);send();#16000000;
        if(page!=2 || volume!=100 || keys!==28'h8000003 || nz[3]<500) $fatal(1,"large keyboard/volume");
        connected=0;#100000;
        if(keys!==28'h8000000) $fatal(1,"disconnect killed physical or left touch stuck");
        if(fft_count<1 || pcm_count<2500) $fatal(1,"coverage");
        $display("PASS touch_system28: chord + physical, Home keeps playing, Home mute, large keyboard, disconnect, scaled stereo DAC; PCM=%0d FFT=%0d",pcm_count,fft_count);$finish;
    end
    initial begin #100000000;$fatal(1,"touch integration timeout");end
endmodule
