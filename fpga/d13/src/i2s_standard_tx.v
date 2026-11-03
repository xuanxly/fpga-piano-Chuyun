`timescale 1ns/1ps
// 标准I2S：48kHz、左右各32bit时隙、16bit有效PCM；WS变化后隔一位发送MSB。
// 与PT8211共用50MHz与复位，两个整数相位累加器的帧边界严格重合。
module i2s_standard_tx #(parameter integer CLK_HZ=50000000,SAMPLE_HZ=48000)(
 input wire clk,rst_n,input wire signed [15:0] sample_l,sample_r,
 output reg bclk,lrclk,data,output reg frame_tick
);
 localparam integer EDGE_HZ=SAMPLE_HZ*128;
 reg [31:0] fraction;wire [32:0] sum={1'b0,fraction}+EDGE_HZ;
 reg [5:0] bit_index;reg started;reg [31:0] left_word,right_word;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin fraction<=0;bclk<=0;lrclk<=0;data<=0;frame_tick<=0;bit_index<=0;started<=0;left_word<=0;right_word<=0;end
  else begin
   frame_tick<=0;
   if(!started)begin started<=1;left_word<={sample_l,16'd0};right_word<={sample_r,16'd0};frame_tick<=1;end
   else if(sum>=CLK_HZ)begin
    fraction<=sum-CLK_HZ;bclk<=!bclk;
    if(bclk)begin // 下降沿更新；接收方在上升沿采样。
     bit_index<=bit_index+1'b1;
     if(bit_index==63)begin
      lrclk<=0;data<=right_word[0];left_word<={sample_l,16'd0};right_word<={sample_r,16'd0};frame_tick<=1;
     end else if(bit_index==31)begin lrclk<=1;data<=left_word[0];end
     else if(bit_index<31)data<=left_word[31-bit_index];
     else data<=right_word[63-bit_index];
    end
   end else fraction<=sum[31:0];
  end
 end
endmodule
