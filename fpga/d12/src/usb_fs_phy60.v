`timescale 1ns/1ps
// USB Full-Speed数字收发器：60MHz/12Mbps=5拍每位，仅用于现有板上USB1。
// 外部15k下拉由NEO Dock提供；复位SE0由上层控制。无Low/High-Speed或Hub支持。
module usb_fs_phy60(
    input wire clk,rst_n,dp_i,dm_i,force_se0,
    input wire tx_start,input wire [3:0] tx_length,input wire [87:0] tx_packet,
    output reg tx_busy,tx_done,output wire dp_o,dm_o,oe,
    output reg rx_busy,rx_valid,rx_error,rx_crc_good,
    output reg [6:0] rx_length,output reg [535:0] rx_packet,
    output wire [1:0] line_state
);
    (* syn_preserve=1, ASYNC_REG="TRUE" *) reg [1:0] dp_sync,dm_sync;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin dp_sync<=0;dm_sync<=0;end
        else begin dp_sync<={dp_sync[0],dp_i};dm_sync<={dm_sync[0],dm_i};end
    end
    assign line_state={dp_sync[1],dm_sync[1]}; // J=10,K=01,SE0=00,SE1=11。
    reg tx_j,tx_se0;reg [2:0] tx_phase,tx_ones,tx_bit;
    reg [3:0] tx_byte,tx_len;reg [87:0] tx_hold;reg [2:0] tx_state;
    reg tx_last;wire [7:0] tx_value=tx_byte==0?8'h80:(tx_hold >> ((tx_byte-1)*8));
    wire tx_dbit=tx_value[tx_bit];
    assign oe=force_se0 || tx_busy;
    assign dp_o=force_se0?1'b0:(!tx_se0 && tx_j);
    assign dm_o=force_se0?1'b0:(!tx_se0 && !tx_j);
    // TX在位边界更新NRZI。连续六个1后插入0，含包尾边界的填充位。
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            tx_busy<=0;tx_done<=0;tx_j<=1;tx_se0<=0;tx_phase<=0;tx_ones<=0;
            tx_bit<=0;tx_byte<=0;tx_len<=0;tx_hold<=0;tx_state<=0;tx_last<=0;
        end else begin
            tx_done<=0;
            if(force_se0) begin tx_busy<=0;tx_se0<=0;tx_state<=0;tx_j<=1;end
            else if(!tx_busy) begin
                if(tx_start && tx_length!=0 && tx_length<=11) begin
                    tx_busy<=1;tx_hold<=tx_packet;tx_len<=tx_length;
                    tx_j<=1;tx_se0<=0;tx_phase<=0;tx_ones<=0;tx_bit<=0;tx_byte<=0;tx_last<=0;tx_state<=0;
                end
            end else if(tx_phase==0) begin
                tx_phase<=4;
                case(tx_state)
                    0: begin
                        if(tx_ones==6) begin tx_j<=~tx_j;tx_ones<=0;end
                        else if(tx_last) begin tx_se0<=1;tx_state<=1;end
                        else begin
                            if(!tx_dbit) begin tx_j<=~tx_j;tx_ones<=0;end
                            else tx_ones<=tx_ones+1'b1;
                            if(tx_bit==7) begin
                                tx_bit<=0;
                                if(tx_byte==tx_len) tx_last<=1;else tx_byte<=tx_byte+1'b1;
                            end else tx_bit<=tx_bit+1'b1;
                        end
                    end
                    1: tx_state<=2; // SE0第二个位时间。
                    2: begin tx_se0<=0;tx_j<=1;tx_state<=3;end
                    3: begin tx_busy<=0;tx_done<=1;end // J保持一位后释放总线。
                    default: tx_busy<=0;
                endcase
            end else tx_phase<=tx_phase-1'b1;
        end
    end

    function [15:0] crc_byte(input [15:0] c,input [7:0] b);
        reg [15:0] q;integer j;begin
            q=c;for(j=0;j<8;j=j+1) q=(q[0]^b[j])?((q>>1)^16'ha001):(q>>1);crc_byte=q;
        end
    endfunction
    reg [1:0] old_line;reg [2:0] rx_phase,rx_bit,rx_ones;
    reg rx_last_j,rx_sync_done,rx_bad;reg [7:0] rx_shift;
    reg [6:0] rx_count;reg [15:0] rx_crc;reg [1:0] rx_se0_count;
    reg [11:0] rx_age;reg [535:0] rx_work;
    wire differential=line_state==2'b10 || line_state==2'b01;
    wire transition=differential && (old_line==2'b10 || old_line==2'b01) && line_state!=old_line;
    wire decoded_bit=(line_state==2'b10)==rx_last_j;
    wire [7:0] received_byte={decoded_bit,rx_shift[7:1]};
    // 双触发器同步后，在位中心采样；每个有效J/K跳变重新对齐采样点。
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            old_line<=0;rx_busy<=0;rx_valid<=0;rx_error<=0;rx_crc_good<=0;rx_packet<=0;rx_length<=0;
            rx_phase<=0;rx_bit<=0;rx_ones<=0;rx_last_j<=1;rx_sync_done<=0;rx_bad<=0;
            rx_shift<=0;rx_count<=0;rx_crc<=16'hffff;rx_se0_count<=0;rx_age<=0;rx_work<=0;
        end else begin
            old_line<=line_state;rx_valid<=0;rx_error<=0;
            if(oe) begin rx_busy<=0;rx_phase<=0;end
            else if(!rx_busy) begin
                if(old_line==2'b10 && line_state==2'b01) begin
                    rx_busy<=1;rx_phase<=2;rx_bit<=0;rx_ones<=0;rx_last_j<=1;
                    rx_sync_done<=0;rx_bad<=0;rx_count<=0;rx_crc<=16'hffff;rx_se0_count<=0;rx_age<=0;rx_work<=0;
                end
            end else begin
                rx_age<=rx_age+1'b1;
                if(rx_age==4095 || line_state==2'b11) begin rx_busy<=0;rx_error<=1;end
                else if(transition && rx_se0_count==0) rx_phase<=2;
                else if(rx_phase!=0) rx_phase<=rx_phase-1'b1;
                else begin
                    rx_phase<=4;
                    if(line_state==0) begin
                        if(rx_se0_count<3) rx_se0_count<=rx_se0_count+1'b1;
                    end else if(rx_se0_count!=0) begin
                        rx_busy<=0;
                        if(rx_se0_count==2 && line_state==2'b10 && rx_sync_done && rx_bit==0 && !rx_bad && rx_count!=0) begin
                            rx_packet<=rx_work;rx_length<=rx_count;rx_valid<=1;
                            rx_crc_good<=rx_crc==16'hb001; // 含线上反码CRC16后的固定余数。
                        end else rx_error<=1;
                    end else begin
                        rx_last_j<=line_state==2'b10;
                        if(rx_ones==6) begin
                            rx_ones<=0;if(decoded_bit) rx_bad<=1; // 填充位必须为0。
                        end else begin
                            rx_shift<=received_byte;
                            if(decoded_bit) rx_ones<=rx_ones+1'b1;else rx_ones<=0;
                            if(rx_bit==7) begin
                                rx_bit<=0;
                                if(!rx_sync_done) begin
                                    rx_sync_done<=1;if(received_byte!=8'h80) rx_bad<=1;
                                end else if(rx_count<67) begin
                                    rx_work[rx_count*8+:8]<=received_byte;rx_count<=rx_count+1'b1;
                                    if(rx_count==0) begin
                                        if(received_byte[7:4] != ~received_byte[3:0]) rx_bad<=1;
                                    end else rx_crc<=crc_byte(rx_crc,received_byte);
                                end else rx_bad<=1;
                            end else rx_bit<=rx_bit+1'b1;
                        end
                    end
                end
            end
        end
    end
endmodule
