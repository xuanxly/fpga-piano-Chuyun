`timescale 1ns/1ps
module tb_master_volume28;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,sample_valid=0;reg signed [15:0] sample_in=0;reg [6:0] percent=25;
    wire signed [15:0] sample_out;wire [8:0] gain;master_volume28 dut(.*);
    integer ref_gain=64,old_gain,value,expected,n,p,checks=0;
    task sample(input integer v);begin
        @(negedge clk);sample_in=v;sample_valid=1;old_gain=ref_gain;
        expected=(v*old_gain)/256;
        if(ref_gain<((percent>=100)?256:(percent*256+50)/100)) ref_gain++;
        else if(ref_gain>((percent>=100)?256:(percent*256+50)/100)) ref_gain--;
        @(negedge clk);sample_valid=0;@(negedge clk);
        if($signed(sample_out)!==expected || gain!==ref_gain)
            $fatal(1,"volume got=%d expected=%d gain=%d ref=%d",sample_out,expected,gain,ref_gain);
        checks++;
    end endtask
    initial begin
        #31;rst_n=1;
        for(p=0;p<=100;p=p+25) begin
            percent=p;
            for(n=0;n<270;n++) sample((n%2) ? 16384 : -16384);
            for(n=0;n<100;n++) sample(n*325-16000);
        end
        percent=0;repeat(270) sample(-32768);if(sample_out!=0 || gain!=0) $fatal(1,"mute");
        percent=100;repeat(270) sample(32767);if(sample_out!=32767) $fatal(1,"unity");
        sample(-32768);if(sample_out!=-32768) $fatal(1,"signed minimum");
        $display("PASS master_volume28: %d independent integer-reference samples, gain slew, signed limits, 0/100%%",checks);$finish;
    end
endmodule
