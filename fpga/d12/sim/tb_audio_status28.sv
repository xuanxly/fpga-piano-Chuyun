`timescale 1ns/1ps
module tb_audio_status28;
    reg clk=0;always #10 clk=~clk;
    reg rst=0,adc=0,done=0,ready=0,valid=0,fft=0,pa=1;
    reg [27:0] keys=0;reg signed [15:0] pcm=0;reg [2:0] fault=0;wire [31:0] status;
    audio_status28 #(.WINDOW_CYCLES(8)) dut(clk,rst,adc,done,ready,valid,fft,keys,pcm,pa,fault,status);
    initial begin
        #101;rst=1;repeat(8) @(negedge clk);
        if(status[15:8]!==0 || status[7:0]!==8'h40) $fatal(1,"Silent startup status");
        adc=1;done=1;ready=1;valid=1;fft=1;pa=0;keys=1;pcm=-32768;
        repeat(8) @(negedge clk);
        if(status[23:8]!==16'h8000 || status[7:0]!==8'hff) $fatal(1,"PCM magnitude or flags");
        fault=3'b101;pa=1;pcm=0;
        repeat(16) @(negedge clk);
        if(status[26:24]!==3'b101 || status[23:8]!==0 || status[6:4]!==0) $fatal(1,"Fault or zero PCM status");
        $display("PASS audio_status28: silence, nonzero PCM including -32768, peak decay and fault/mute flags");$finish;
    end
endmodule
