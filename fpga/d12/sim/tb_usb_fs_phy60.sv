`timescale 1ns/1ps
module tb_usb_fs_phy60;
    reg clk=0;always #8.333333 clk=~clk;reg rst_n=0;
    wire dp,dm,po,mo,oe,drive,pd,md;assign dp=oe?po:(drive?pd:1'b1);assign dm=oe?mo:(drive?md:1'b0);
    reg start=0;reg [3:0] len=0;reg [87:0] packet=0;wire busy,done,rb,rv,re,crc;
    wire [6:0] rl;wire [535:0] rp;wire [1:0] line_state;
    usb_fs_phy60 dut(clk,rst_n,dp,dm,1'b0,start,len,packet,busy,done,po,mo,oe,rb,rv,re,crc,rl,rp,line_state);
    usb_device_bfm dev(dp,dm,oe,drive,pd,md);
    integer n,received=0;reg [535:0] observed;reg [511:0] body;
    always @(posedge clk) begin #1;if(rv) received++;end
    task check_rx(input real period,input corrupt);begin
        fork
            dev.send_data(body,64,1,corrupt,period);
            begin
                wait(rv);#1;if(rl!=67 || rp[7:0]!=8'h4b || rp[519:8]!==body || crc==corrupt)
                    $fatal(1,"FS RX data/CRC period=%f length=%0d crc=%b error=%b",period,rl,crc,re);
            end
        join
        #1000;
    end endtask
    initial begin
        body=0;for(n=0;n<64;n++) body[n*8+:8]=(n%3==0)?8'hff:n;
        #201;rst_n=1;#1000;
        check_rx(83.333333,0);check_rx(82.1,0);check_rx(84.5,0);check_rx(83.333333,1);
        fork
            begin @(negedge clk);packet=88'h1234ffff00ff00554bc380;len=11;start=1;@(negedge clk);start=0;wait(done);end
            begin dev.receive_host(observed,n);if(n!=11 || observed[87:0]!==88'h1234ffff00ff00554bc380) $fatal(1,"TX packet mismatch n=%d %h",n,observed);end
        join
        if(received!=4) $fatal(1,"RX coverage %d",received);
        $display("PASS usb_fs_phy60: independent bit-level BFM, full 64-byte payload, stuffing, +/- clock offset, CRC corruption, TX/EOP");$finish;
    end
    initial begin #1000000;$fatal(1,"PHY timeout rb=%b rv=%b err=%b len=%d",rb,rv,re,rl);end
endmodule
