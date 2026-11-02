`timescale 1ns/1ps
module tb_media_spi;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,start=0;reg [7:0] tx=0;reg [15:0] half_div=2;
    wire busy,sck,mosi;wire [7:0] rx;reg miso=1;
    sd_spi_byte dut(.*);
    integer edges=0,checks=0,n,i;reg [7:0] seen,response;
    always @(posedge sck) if(busy)begin seen={seen[6:0],mosi};edges++;end
    always @(negedge sck)if(busy)miso=response[7-edges%8];
    task run_byte(input [7:0] a,b,input integer div);
        begin
            @(negedge clk);half_div=div;tx=a;response=b;miso=b[7];seen=0;edges=0;start=1;
            @(negedge clk);start=0;wait(!busy);#1;
            if(rx!==b||seen!==a||edges!=8||sck)$fatal(1,"SPI mode0 a=%h seen=%h b=%h got=%h edges=%0d",a,seen,b,rx,edges);
            checks++;
        end
    endtask
    initial begin
        #51;rst_n=1;for(i=0;i<256;i++)run_byte(i,i^8'hc3,2);
        run_byte(8'h95,8'haa,64);run_byte(8'hff,8'hff,1);
        rst_n=0;#1;if(busy||sck||!mosi)$fatal(1,"SPI reset");
        $display("PASS media_spi checks=%0d: every TX byte, independent RX bytes, mode0 edge order, init/run clocks and reset",checks);$finish;
    end
endmodule
