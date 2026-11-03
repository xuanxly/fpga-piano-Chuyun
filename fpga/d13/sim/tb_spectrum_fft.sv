`timescale 1ns/1ps
module tb_spectrum_fft;
    reg clk=0; always #10 clk=~clk;
    reg rst_n=0,pcm_valid=0; reg signed [15:0] pcm=0;
    wire frame_valid,overrun,bin_valid; wire [255:0] levels;
    wire [9:0] bin_index; wire signed [17:0] bin_real,bin_imag;
    spectrum_fft dut(.*);
    reg [15:0] samples[0:12287]; reg [35:0] expected[0:6137]; reg [255:0] expected_bands[0:5];
    integer checked=0,frames=0,cycles=0,start_cycle=0,max_processing=0;
    always @(posedge clk) if(rst_n) begin
        cycles=cycles+1;
        if(overrun) $fatal(1,"FFT processing overrun");
        if(bin_valid) begin
            if(bin_index!=checked%1023+1) $fatal(1,"FFT bin ordering");
            if({bin_real,bin_imag} !== expected[checked])
                $fatal(1,"FFT numerical mismatch frame=%0d bin=%0d got=%0d,%0d expected=%h",frames,bin_index,bin_real,bin_imag,expected[checked]);
            checked=checked+1;
        end
        if(frame_valid) begin
            if(levels !== expected_bands[frames]) $fatal(1,"32-band output mismatch frame=%0d",frames);
            if(cycles-start_cycle>max_processing) max_processing=cycles-start_cycle;
            frames=frames+1;
        end
    end
    initial begin
        $readmemh("spectrum_samples.hex",samples); $readmemh("spectrum_expected.hex",expected); $readmemh("spectrum_bands.hex",expected_bands);
        repeat(4) @(negedge clk); rst_n=1;
        for(integer f=0;f<6;f=f+1) begin
            for(integer n=0;n<2048;n=n+1) begin
                @(negedge clk); pcm=samples[f*2048+n]; pcm_valid=1;
                @(negedge clk); pcm_valid=0;
                if(n!=2047) repeat(127) @(negedge clk); // 比真实 48 kHz 更紧的采集预算
            end
            start_cycle=cycles;
            wait(frames==f+1);
        end
        if(checked!=6138 || max_processing>200000) $fatal(1,"coverage or processing budget");
        $display("PASS spectrum_fft frames=%0d exact_complex_bins=%0d max_process_cycles=%0d",frames,checked,max_processing);
        $finish;
    end
    initial begin #100000000; $fatal(1,"FFT timeout"); end
endmodule
