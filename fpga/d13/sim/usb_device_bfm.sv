`timescale 1ns/1ps
// 独立按USB位时间驱动/观察总线，不借用DUT收发器或内部包信号。
module usb_device_bfm(input wire dp,dm,host_oe,output reg drive=0,dp_drive=1,dm_drive=0);
    localparam real BIT_NS=83.333333333;
    task receive_host(output reg [535:0] packet,output integer length);
        reg last_j,bit_value;reg [7:0] byte_value;integer bit_index,ones,byte_index;begin
            packet=0;length=0;last_j=1;bit_index=0;ones=0;byte_index=0;byte_value=0;
            wait(host_oe && dp===0 && dm===1);#(BIT_NS/2);
            while(!(dp===0 && dm===0)) begin
                if(!host_oe || (dp===1 && dm===1)) $fatal(1,"BFM illegal host line");
                bit_value=(dp==last_j);last_j=dp;
                if(ones==6) begin if(bit_value) $fatal(1,"host bit stuffing");ones=0;end
                else begin
                    if(bit_value) ones++;else ones=0;
                    byte_value[bit_index]=bit_value;bit_index++;
                    if(bit_index==8) begin
                        if(byte_index==0) begin if(byte_value!=8'h80) $fatal(1,"host SYNC=%h",byte_value);end
                        else begin packet[(byte_index-1)*8+:8]=byte_value;length++;end
                        byte_index++;bit_index=0;byte_value=0;
                    end
                end
                #(BIT_NS);
            end
            if(bit_index!=0) $fatal(1,"host byte alignment at EOP");
            #(BIT_NS);if(dp!==0 || dm!==0) $fatal(1,"host EOP too short");
            #(BIT_NS);if(dp!==1 || dm!==0) $fatal(1,"host EOP missing J");
        end
    endtask
    task send_packet(input [535:0] packet,input integer length,input real period);
        integer i,j,ones;reg state_j,bit_value;reg [7:0] b;begin
            wait(!host_oe);#(BIT_NS*2.2);drive=1;state_j=1;ones=0;
            for(i=0;i<=length;i++) begin
                b=i==0?8'h80:packet[(i-1)*8+:8];
                for(j=0;j<8;j++) begin
                    bit_value=b[j];if(!bit_value) begin state_j=~state_j;ones=0;end else ones++;
                    dp_drive=state_j;dm_drive=~state_j;#(period);
                    if(ones==6) begin state_j=~state_j;dp_drive=state_j;dm_drive=~state_j;#(period);ones=0;end
                end
            end
            dp_drive=0;dm_drive=0;#(period*2);dp_drive=1;dm_drive=0;#(period);drive=0;
        end
    endtask
    function [15:0] crc16(input [511:0] payload,input integer length);
        reg [15:0] c;integer i;begin
            c=16'hffff;for(i=0;i<length*8;i++) begin
                if(c[0]^payload[i]) c=(c>>1)^16'ha001;else c=c>>1;
            end
            crc16=~c;
        end
    endfunction
    task send_data(input [511:0] payload,input integer length,input toggle,input corrupt,input real period);
        reg [535:0] p;reg [15:0] c;begin
            p=0;p[7:0]=toggle?8'h4b:8'hc3;p[519:8]=payload;c=crc16(payload,length);
            if(corrupt) c=c^16'h0100;p[(length+1)*8+:16]=c;send_packet(p,length+3,period);
        end
    endtask
    task handshake(input [7:0] pid);begin send_packet({528'd0,pid},1,BIT_NS);end endtask
endmodule
