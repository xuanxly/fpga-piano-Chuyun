`timescale 1ns/1ps
module tb_mcp3008_scan;
    reg clk=0; always #10 clk=~clk;          // 使用真实 50 MHz / 500 kHz 比例
    reg rst_n=0;
    wire cs_n,sck,mosi,miso,valid;
    wire [2:0] channel; wire [9:0] sample;
    reg [79:0] levels={10'd999,10'd1000,10'd682,10'd341,10'd512,10'd1,10'd1023,10'd0};
    wire integer transactions;
    mcp3008_scan dut(clk,rst_n,miso,cs_n,sck,mosi,valid,channel,sample);
    mcp3008_model adc(cs_n,sck,mosi,levels,miso,transactions);
    integer checks=0,count=0,expected_channel=0;
    time last_time[0:6]; time last_rise=0;
    reg previous_valid=0;
    task check(input bit condition,input string reason);
        if (!condition) $fatal(1,"%s",reason); checks++;
    endtask
    always @(posedge sck) begin
        if (last_rise != 0 && adc.edge_count != 1)
            check($time-last_rise == 2000,"SPI period must be 2 us");
        last_rise=$time;
    end
    always @(negedge cs_n) last_rise=0;
    always @(posedge clk) begin
        #1;
        if (rst_n) begin
            check(!(valid && previous_valid),"raw_valid is a single-cycle pulse");
            previous_valid=valid;
            if (valid) begin
                check(channel==expected_channel,"CH0 to CH6 polling order");
                check(sample===levels[channel*10 +: 10],"all ten bits match independent channel stimulus");
                check(cs_n && !sck,"result is published only after CS returns high");
                if (last_time[channel]!=0)
                    check($time-last_time[channel]>=999000 && $time-last_time[channel]<=1001000,"each channel is updated about once per ms");
                last_time[channel]=$time;
                expected_channel=(expected_channel+1)%7; count++;
            end
        end
    end
    initial begin
        for(integer i=0;i<7;i++) last_time[i]=0;
        repeat(4) @(negedge clk);
        check(cs_n && !sck && !valid,"ADC reset outputs"); rst_n=1;
        wait(count==21);                       // 包含 0、满量程、最低位、最高位和交替位
        @(negedge clk); levels={8{10'd1023}};
        wait(count==35);
        check(transactions==35,"one completed SPI transaction per published sample");
        $display("PASS mcp3008_scan samples=%0d checks=%0d",count,checks); $finish;
    end
    initial begin #6000000; $fatal(1,"MCP3008 scan timeout"); end
endmodule
