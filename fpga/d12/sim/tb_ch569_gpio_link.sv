`timescale 1ns/1ps
module tb_ch569_gpio_link;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,allow=0,ready=0,req=0,ack=0,pop=0,push=0,clear=0;reg [3:0] mdata=0;reg [7:0] tdata=0;
    wire rack,treq,oe,present;wire [3:0] fdata;wire [7:0] rdata;wire [9:0] count,free;
    ch569_gpio_link d(clk,rst,allow,ready,req,ack,mdata,rack,treq,fdata,oe,pop,rdata,count,push,tdata,free,clear,present);
    task clocks(input integer n);repeat(n)@(negedge clk);endtask
    task nibble(input [3:0] v);begin mdata=v;clocks(2);req=~req;wait(rack===req);clocks(2);end endtask
    task byte_in(input [7:0] v);begin nibble(v[3:0]);nibble(v[7:4]);end endtask
    task byte_out(input [7:0] expected);reg [7:0] v;begin
        wait(treq!==ack);v[3:0]=fdata;clocks(7);ack=treq;clocks(2);
        wait(treq!==ack);v[7:4]=fdata;clocks(3);ack=treq;clocks(8);
        if(v!==expected)$fatal(1,"MCU receive got %h expected %h",v,expected);
    end endtask
    initial begin
        clocks(3);rst=1;clocks(3);if(!oe)$fatal(1,"Startup data outputs enabled");
        ready=1;clocks(5);for(integer i=0;i<40;i++)byte_in(i^8'ha5);
        if(count!=40||!oe)$fatal(1,"RX failed or unauthenticated output enabled");
        for(integer i=0;i<40;i++)begin clocks(2);if(rdata!==(i^8'ha5))$fatal(1,"RX order/stale queue data at %0d got%h",i,rdata);pop=1;clocks(1);pop=0;end
        if(count)$fatal(1,"RX did not drain");
        allow=1;clocks(3);if(oe)$fatal(1,"Authenticated enable failed");
        for(integer i=0;i<40;i++)begin tdata=i*3;push=1;clocks(1);push=0;clocks(1);end
        for(integer i=0;i<40;i++)byte_out(i*3);
        if(free!=512)$fatal(1,"TX did not drain");
        // 真实READ回复长521字节，超过512字节FIFO；验证背压、指针回绕与持续传输。
        fork
          begin for(integer i=0;i<1100;i++)byte_in(i^8'h6d);end
          begin
            for(integer i=0;i<1100;i++)begin
              wait(count!=0);clocks(2);if(rdata!==((i^8'h6d)&255))$fatal(1,"Wrapped RX %0d got%h",i,rdata);
              pop=1;clocks(1);pop=0;clocks(2);
            end
          end
        join
        fork
          begin for(integer i=0;i<1100;i++)begin
            @(negedge clk);while(free==0)@(negedge clk);
            tdata=(i*11)&255;push=1;clocks(1);push=0;
          end end
          begin for(integer i=0;i<1100;i++)byte_out((i*11)&255);end
        join
        if(count||free!=512)$fatal(1,"Wrapped FIFOs did not drain");
        #2;ready=0;#1;if(!oe)$fatal(1,"MCU reset did not asynchronously release pads");
        clocks(8);if(count||free!=512)$fatal(1,"MCU reset retained FIFO data");
        $display("PASS CH569 GPIO async handshake,1140 RX/TX bytes,512 FIFO backpressure+wrap,stalled ack,INIT highZ,async shutdown/reset");$finish;
    end
    initial begin #2000000;$fatal(1,"GPIO link timeout");end
endmodule
