`timescale 1ns/1ps
// 只按一个接近触发阈值的键，不用28键大和弦掩盖弱压力/单键链路问题。
module tb_single_key28;
    reg clk=0;always #10 clk=~clk;
    reg rst=0;wire cs,sck,mosi;wire [3:0] miso;
    pressure_piano_28_top top(.sys_clk(clk),.rst_n(rst),.enc_a(1'b1),.enc_b(1'b1),.dark_button_n(1'b1),
        .adc_miso(miso),.adc_cs_n(cs),.adc_sck(sck),.adc_mosi(mosi));
    reg [79:0] values[0:3];wire integer transactions[0:3];
    genvar b;generate for(b=0;b<4;b=b+1) begin:model
        mcp3008_model m(cs,sck,mosi,values[b],miso[b],transactions[b]);
    end endgenerate
    integer i,nonzero=0,peak=0,frames=0;integer mag;
    always @(posedge clk) if(top.pcm_valid) begin
        mag=$signed(top.pcm);if(mag<0) mag=-mag;
        if(mag>peak) peak=mag;if(mag!=0) nonzero=nonzero+1;
    end
    always @(posedge clk) if(top.fft_valid && top.levels!=0) frames=frames+1;
    initial begin
        for(i=0;i<4;i=i+1) values[i]=0;
        #201;rst=1;#2000000;values[0][9:0]=50;
        #98000000;
        if(top.keys!==28'd1 || nonzero<1000 || peak<4 || frames<1 || top.pa_en || top.audio_fault)
            $fatal(1,"Weak single-key audio failed keys=%h nonzero=%0d peak=%0d FFT=%0d PA=%b fault=%b",top.keys,nonzero,peak,frames,top.pa_en,top.audio_fault);
        if(!top.diagnostic[4] || !top.diagnostic[6]) $fatal(1,"Real PCM not reflected in status strip");
        $display("PASS single_key28: raw=50, nonzero=%0d peak=%0d FFT=%0d; only C3 pressed, actual PCM and diagnostic observed",nonzero,peak,frames);$finish;
    end
endmodule
