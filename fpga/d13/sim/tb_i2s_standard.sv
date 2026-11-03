`timescale 1ns/1ps
module tb_i2s_standard;
 reg clk=0,rst_n=0;always #10 clk=~clk;
 reg signed [15:0] sample_l=16'sh1234,sample_r=16'sh9abc;
 wire bclk,lrclk,data,frame_tick;wire pt_tick,pb,pw,pd;
 i2s_standard_tx dut(.*);
 pt8211_tx old(.clk(clk),.rst_n(rst_n),.sample_l(sample_l),.sample_r(sample_r),.sample_tick(pt_tick),.dac_bck(pb),.dac_ws(pw),.dac_din(pd));
 reg [31:0] expected_l[0:255],expected_r[0:255];integer written=0,read_frame=0,words=0,bits=0;
 reg old_ws=0,collect=0,channel=0;reg [31:0] word_value;time changed;
 always @(negedge clk)if(rst_n)begin
  if(frame_tick!==pt_tick)$fatal(1,"I2S/PT8211 frame drift");
  if(frame_tick)begin
   expected_l[written]={sample_l,16'd0};expected_r[written]={sample_r,16'd0};written++;
   sample_l<=sample_l+16'h1357;sample_r<=sample_r-16'h2345;
  end
 end
 always @(data or lrclk)changed=$time;
 always @(posedge bclk)if(rst_n)begin
  if($time-changed<140)$fatal(1,"I2S setup margin <140ns");
  if(collect)begin
   word_value={word_value[30:0],data};bits++;
   if(bits==32)begin
    if(word_value!==(channel?expected_r[read_frame]:expected_l[read_frame]))$fatal(1,"I2S decoded channel/frame%0d/%0d got%h",channel,read_frame,word_value);
    words++;if(channel)read_frame++;
   end
  end
  if(lrclk!=old_ws)begin collect=1;channel=lrclk;bits=0;word_value=0;old_ws=lrclk;end
 end
 initial begin #101;rst_n=1;wait(words>=127);rst_n=0;#71;rst_n=1;
  // 复位后重新清空独立接收模型，再验证多帧。
  written=0;read_frame=0;words=0;bits=0;collect=0;channel=0;old_ws=0;word_value=0;
  wait(words>=31);$display("PASS standard I2S: 158 decoded 32-bit words, one-bit delay, stereo, padding, frame lock and reset");$finish;end
 initial begin #4000000;$fatal(1,"I2S timeout");end
endmodule
