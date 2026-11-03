`timescale 1ns/1ps
// 32份独立相位、步长和使能；375Hz..12kHz，对齐2048点FFT的第16..512频点。
// 只在验证页主动START后发声。没有音频录音ROM，每帧共享正弦流水线计算32声部。
module validation_tones32(input wire clk,rst_n,sample_tick,enable,input wire [5:0] count,
 output reg signed [15:0] pcm,output reg valid,busy,ready,fault,output reg [5:0] active_units);
 (* syn_ramstyle="distributed_ram" *)reg [31:0] phases[0:31];
 (* syn_ramstyle="distributed_ram" *)reg [15:0] envelopes[0:31]; // 各声部自己的起音包络，不以共享标志冒充独立状态。
 reg [4:0] index,init_index;reg [2:0] slot;reg [5:0] units;
 reg running,frame_enable;reg [31:0] phase_query,phase_next;
 reg [15:0] envelope;reg signed [32:0] scaled;
 wire signed [15:0] sine;reg signed [21:0] accumulator;
 sine28_shared u_sine(.clk(clk),.phase(phase_query),.sample_out(sine));
 always @(posedge clk)begin
  if(!ready)begin phases[init_index]<=0;envelopes[init_index]<=0;end
  else if(busy&&slot==7)begin phases[index]<=phase_next;envelopes[index]<=envelope;end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin ready<=0;init_index<=0;index<=0;slot<=0;units<=1;running<=0;frame_enable<=0;
   phase_query<=0;phase_next<=0;envelope<=0;scaled<=0;accumulator<=0;pcm<=0;valid<=0;busy<=0;fault<=0;active_units<=0;end
  else begin
   valid<=0;
   if(!ready)begin if(init_index==31)ready<=1;else init_index<=init_index+1'b1;end
   else if(sample_tick&&!busy)begin
    units<=(count<1)?6'd1:(count>32)?6'd32:count;frame_enable<=enable;
    running<=enable;busy<=1;slot<=0;index<=0;accumulator<=0;
   end else if(busy)begin
    if(sample_tick)fault<=1;
    slot<=slot+1'b1;
    case(slot)
     0:begin
      phase_query<=running?phases[index]:32'd0;
      phase_next<=(running?phases[index]:32'd0)+(({27'd0,index}+32'd1)<<25);
      envelope<=!frame_enable||{1'b0,index}>=units?16'd0:(!running?16'd1024:(envelopes[index]>=64511?16'hffff:envelopes[index]+16'd1024));
     end
     5:scaled<=$signed(sine)*$signed({1'b0,envelope});
     6:if(frame_enable&&{1'b0,index}<units)accumulator<=accumulator+(scaled>>>22);
     7:if(index==31)begin pcm<=accumulator[15:0];valid<=1;busy<=0;active_units<=frame_enable?units:6'd0;end
       else index<=index+1'b1;
     default:begin end
    endcase
   end
  end
 end
endmodule
