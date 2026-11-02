`timescale 1ns/1ps
module mcp3008_scan28 #(
    parameter integer CLK_HZ=50000000, SPI_HZ=500000, KEY_UPDATE_HZ=1000
)(
    input wire clk,rst_n, input wire [3:0] adc_miso,
    output wire adc_cs_n,adc_sck,adc_mosi,
    output reg raw_valid, output reg [4:0] raw_key, output reg [9:0] raw_sample,
    output reg fault                              // 四路接收必须保持同步，错误不被静默忽略
);
    wire [3:0] valid,cs,sck,mosi;
    wire [2:0] channel[0:3]; wire [9:0] sample[0:3];
    genvar g;
    generate for(g=0;g<4;g=g+1) begin: bank
        mcp3008_scan #(.CLK_HZ(CLK_HZ),.SPI_HZ(SPI_HZ),.KEY_UPDATE_HZ(KEY_UPDATE_HZ)) rx(
            .clk(clk),.rst_n(rst_n),.adc_miso(adc_miso[g]),.adc_cs_n(cs[g]),.adc_sck(sck[g]),.adc_mosi(mosi[g]),
            .raw_valid(valid[g]),.raw_channel(channel[g]),.raw_sample(sample[g]));
    end endgenerate
    assign adc_cs_n=cs[0]; assign adc_sck=sck[0]; assign adc_mosi=mosi[0]; // 三路公共输出只使用一个FPGA引脚
    reg [39:0] captured; reg [2:0] captured_channel;
    reg pending; reg [1:0] bank_id;
    wire [4:0] key_number={bank_id,3'b000}-{3'd0,bank_id}+captured_channel; // 7×板号+通道，不使用乘法器
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin raw_valid<=0;raw_key<=0;raw_sample<=0;fault<=0;captured<=0;captured_channel<=0;pending<=0;bank_id<=0;end
        else begin
            raw_valid<=0;
            if(valid[0]) begin
                if(valid!=4'b1111 || pending) fault<=1;
                captured<={sample[3],sample[2],sample[1],sample[0]};captured_channel<=channel[0];bank_id<=0;pending<=1;
            end else if(pending) begin
                raw_valid<=1;raw_key<=key_number;raw_sample<=captured[bank_id*10 +: 10];
                if(bank_id==3) pending<=0;else bank_id<=bank_id+1'b1; // 四路同时采样的数据依次发布
            end
        end
    end
endmodule
