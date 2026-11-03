`timescale 1ns/1ps
// 单次USB事务：SETUP/IN/OUT/SOF；接收CRC错误不ACK，重复DATA由上层toggle去重。
// 此项目只需8字节SETUP与零长度OUT；IN支持端点64字节最大包。
module usb_fs_transaction(
    input wire clk,rst_n,start,input wire [1:0] mode,input wire [6:0] address,
    input wire [3:0] endpoint,out_length,input wire out_toggle,input wire [63:0] out_data,
    input wire [10:0] frame_number,
    output reg busy,done,output reg [2:0] result,
    output reg [6:0] in_length,output reg [511:0] in_data,output reg in_toggle,
    output reg tx_start,output reg [3:0] tx_length,output reg [87:0] tx_packet,
    input wire tx_done,rx_busy,rx_valid,rx_error,rx_crc_good,
    input wire [6:0] rx_length,input wire [535:0] rx_packet
);
    localparam PREP=1,TOKEN=2,TOKEN_WAIT=3,GAP=4,DATA_SEND=5,DATA_WAIT=6,RX_WAIT=7,ACK_GAP=8,ACK_WAIT=9;
    reg [3:0] state;reg [1:0] op;reg [6:0] addr;reg [3:0] ep,n;
    reg toggle;reg [63:0] payload;reg [10:0] frame;
    reg [15:0] crc;reg [3:0] index;reg [87:0] data_packet;reg [11:0] timer;
    function [4:0] crc5(input [10:0] bits_in);
        reg [4:0] q;integer j;begin
            q=5'h1f;for(j=0;j<11;j=j+1) q=(q[0]^bits_in[j])?((q>>1)^5'h14):(q>>1);crc5=~q;
        end
    endfunction
    function [15:0] crc8(input [15:0] c,input [7:0] b);
        reg [15:0] q;integer j;begin
            q=c;for(j=0;j<8;j=j+1) q=(q[0]^b[j])?((q>>1)^16'ha001):(q>>1);crc8=q;
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            busy<=0;done<=0;result<=0;in_length<=0;in_data<=0;in_toggle<=0;
            tx_start<=0;tx_length<=0;tx_packet<=0;state<=0;op<=0;addr<=0;ep<=0;n<=0;
            toggle<=0;payload<=0;frame<=0;crc<=16'hffff;index<=0;data_packet<=0;timer<=0;
        end else begin
            done<=0;tx_start<=0;
            if(!busy) begin
                if(start) begin
                    busy<=1;op<=mode;addr<=address;ep<=endpoint;n<=out_length;toggle<=out_toggle;
                    payload<=out_data;frame<=frame_number;crc<=16'hffff;index<=0;
                    in_length<=0;data_packet<=out_toggle?8'h4b:8'hc3;
                    if(mode==1 || mode==3) state<=TOKEN;else state<=PREP;
                end
            end else case(state)
                PREP: begin
                    if(index<n) begin
                        data_packet[(index+1)*8+:8]<=payload[index*8+:8];crc<=crc8(crc,payload[index*8+:8]);index<=index+1'b1;
                    end else begin data_packet[(n+1)*8+:16]<=~crc;state<=TOKEN;end
                end
                TOKEN: begin
                    tx_length<=3;tx_start<=1;state<=TOKEN_WAIT;
                    if(op==3) tx_packet<={64'd0,crc5(frame),frame,8'ha5};
                    else tx_packet<={64'd0,crc5({ep,addr}),ep,addr,(op==0?8'h2d:(op==1?8'h69:8'he1))};
                end
                TOKEN_WAIT: if(tx_done) begin
                    timer<=0;
                    if(op==3) begin busy<=0;done<=1;result<=0;state<=0;end
                    else if(op==1) state<=RX_WAIT;else state<=GAP;
                end
                GAP: if(timer==15) begin state<=DATA_SEND;timer<=0;end else timer<=timer+1'b1;
                DATA_SEND: begin tx_packet<=data_packet;tx_length<=n+3;tx_start<=1;state<=DATA_WAIT;end
                DATA_WAIT: if(tx_done) begin timer<=0;state<=RX_WAIT;end
                RX_WAIT: begin
                    if(rx_busy) timer<=0;else timer<=timer+1'b1;
                    if(rx_valid) begin
                        if(rx_length==1 && rx_packet[7:0]==8'h5a) begin result<=1;done<=1;busy<=0;end
                        else if(rx_length==1 && rx_packet[7:0]==8'h1e) begin result<=2;done<=1;busy<=0;end
                        else if(op!=1 && rx_length==1 && rx_packet[7:0]==8'hd2) begin result<=0;done<=1;busy<=0;end
                        else if(op==1 && rx_length>=3 && rx_length<=67 && rx_crc_good &&
                                (rx_packet[7:0]==8'hc3 || rx_packet[7:0]==8'h4b)) begin
                            in_length<=rx_length-3;in_data<=rx_packet[519:8];in_toggle<=rx_packet[7:0]==8'h4b;
                            timer<=0;state<=ACK_GAP; // 包含CRC校验的完整DATA才能进入ACK。
                        end else begin result<=4;done<=1;busy<=0;end
                    end else if(rx_error) begin result<=4;done<=1;busy<=0;end
                    else if(timer==1800) begin result<=3;done<=1;busy<=0;end
                end
                ACK_GAP: if(timer==7) begin
                    tx_start<=1;tx_length<=1;tx_packet<=8'hd2;state<=ACK_WAIT;
                end else timer<=timer+1'b1;
                ACK_WAIT: if(tx_done) begin result<=0;done<=1;busy<=0;state<=0;end
                default: begin busy<=0;done<=1;result<=4;state<=0;end
            endcase
        end
    end
endmodule
