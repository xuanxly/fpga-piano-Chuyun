`timescale 1ns/1ps
module tb_scan28;
    reg clk=0;always #10 clk=~clk;reg rst_n=0;
    wire cs,sck,mosi,valid,fault;wire [3:0] miso;wire [4:0] key;wire [9:0] sample;
    mcp3008_scan28 dut(clk,rst_n,miso,cs,sck,mosi,valid,key,sample,fault);
    reg [79:0] values[0:3];wire integer transactions[0:3];
    genvar b;generate for(b=0;b<4;b=b+1) begin:model
        mcp3008_model m(cs,sck,mosi,values[b],miso[b],transactions[b]);
    end endgenerate
    integer n=0,k,j,bank,channel,expected;time last_seen[0:27];
    always @(posedge clk) if(rst_n) begin
        #1;
        if(fault) $fatal(1,"ADC banks desynchronized");
        if(dut.cs!={4{cs}} || dut.sck!={4{sck}} || dut.mosi!={4{mosi}}) $fatal(1,"shared SPI timing diverged");
        if(valid) begin
            bank=n%4;channel=(n/4)%7;expected=bank*7+channel;
            if(key!==expected || sample!==values[bank][channel*10+:10]) $fatal(1,"ADC board/channel mapping n=%0d key=%0d sample=%0d",n,key,sample);
            if(last_seen[key]!=0 && ($time-last_seen[key]<999000 || $time-last_seen[key]>1001000)) $fatal(1,"key refresh not 1kHz");
            last_seen[key]=$time;n=n+1;
        end
    end
    initial begin
        for(j=0;j<4;j=j+1) begin values[j]=0;for(k=0;k<8;k=k+1) values[j][k*10+:10]=80+j*210+k*17;end
        for(k=0;k<28;k=k+1) last_seen[k]=0;
        #201;rst_n=1;#4000000;
        if(n<100) $fatal(1,"insufficient four-bank scan coverage");
        for(j=0;j<4;j=j+1) if(transactions[j]<25) $fatal(1,"missing ADC transactions");
        $display("PASS scan28: %0d distinct board/channel samples, shared SPI protocol and 1kHz/key checked",n);$finish;
    end
endmodule
