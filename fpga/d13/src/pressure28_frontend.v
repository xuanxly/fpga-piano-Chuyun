`timescale 1ns/1ps
module pressure28_frontend #(
    parameter [279:0] BASELINE={28{10'd0}}, FULL_SCALE={28{10'd1023}},
    parameter integer PRESS_ON=160, PRESS_OFF=100
)(
    input wire clk,rst_n,raw_valid, input wire [4:0] raw_key, input wire [9:0] raw_sample,
    output reg [27:0] key_gate, output reg [335:0] key_pressure,
    output reg fault, output reg update_valid, output reg [4:0] update_key
);
    reg [14:0] fifo[0:7]; reg [2:0] wr_ptr,rd_ptr; reg [3:0] count; // 接收四路连续发布，八项FIFO留出余量
    reg [2:0] state;
    localparam IDLE=0,FILTER=1,PREPARE=2,DIVIDE=3,COMMIT=4;
    wire pop=(state==IDLE && count!=0);
    wire push=(raw_valid && raw_key<28 && (count<8 || pop));
    wire [4:0] head_key=fifo[rd_ptr][14:10];
    reg [9:0] filtered[0:27];
    reg [4:0] key; reg [9:0] raw,old_filter,base,full,new_filter;
    reg [9:0] denominator; reg [23:0] dividend,quotient; reg [10:0] remainder;
    reg [4:0] bits_left; reg [11:0] normalized;
    wire signed [10:0] difference=$signed({1'b0,raw})-$signed({1'b0,old_filter});
    wire signed [10:0] filter_step=(difference>0 && (difference>>>2)==0) ? 11'sd1 : (difference>>>2);
    wire signed [10:0] filter_next=$signed({1'b0,old_filter})+filter_step;
    wire [9:0] positive_delta=new_filter-base;
    wire [23:0] numerator=({14'd0,positive_delta}<<12)-positive_delta; // 乘4095用移位与减法实现
    wire [10:0] trial={remainder[9:0],dividend[23]};
    wire subtract=(trial>={1'b0,denominator});
    wire [23:0] next_quotient={quotient[22:0],subtract};
    integer k;
    always @(posedge clk) if(push) fifo[wr_ptr]<={raw_key,raw_sample};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            wr_ptr<=0;rd_ptr<=0;count<=0;state<=IDLE;key<=0;raw<=0;old_filter<=0;base<=0;full<=0;new_filter<=0;
            denominator<=1;dividend<=0;quotient<=0;remainder<=0;bits_left<=0;normalized<=0;
            key_gate<=0;key_pressure<=0;fault<=0;update_valid<=0;update_key<=0;
            for(k=0;k<28;k=k+1) filtered[k]<=BASELINE[k*10 +: 10];
        end else begin
            update_valid<=0;
            if(raw_valid && !push) fault<=1;      // 越界地址或FIFO满均可在整机验证中观测
            case({push,pop}) 2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;default:begin end endcase
            if(push) wr_ptr<=wr_ptr+1'b1;
            if(pop) rd_ptr<=rd_ptr+1'b1;
            case(state)
                IDLE: if(pop) begin
                    key<=head_key;raw<=fifo[rd_ptr][9:0];old_filter<=filtered[head_key];
                    base<=BASELINE[head_key*10 +: 10];full<=FULL_SCALE[head_key*10 +: 10];state<=FILTER;
                end
                FILTER: begin new_filter<=filter_next[9:0];filtered[key]<=filter_next[9:0];state<=PREPARE;end
                PREPARE: begin
                    if(full<=base || new_filter<=base) begin normalized<=0;state<=COMMIT;end
                    else if(new_filter>=full) begin normalized<=4095;state<=COMMIT;end
                    else begin
                        dividend<=numerator;denominator<=full-base;quotient<=0;remainder<=0;bits_left<=24;state<=DIVIDE;
                    end
                end
                DIVIDE: begin                         // 共享逐位除法器，二十四周期内完成一键归一化
                    dividend<={dividend[22:0],1'b0};quotient<=next_quotient;
                    remainder<=subtract ? trial-denominator : trial;
                    if(bits_left==1) begin normalized<=next_quotient[11:0];state<=COMMIT;end
                    else bits_left<=bits_left-1'b1;
                end
                COMMIT: begin
                    key_pressure[key*12 +: 12]<=normalized;
                    if(full<=base) key_gate[key]<=0;
                    else if(!key_gate[key] && normalized>=PRESS_ON) key_gate[key]<=1;
                    else if(key_gate[key] && normalized<=PRESS_OFF) key_gate[key]<=0;
                    update_key<=key;update_valid<=1;state<=IDLE;
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
