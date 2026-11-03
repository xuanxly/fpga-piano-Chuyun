`timescale 1ns/1ps
// 只测数字事件：门控上升到DAC装载非零PCM。不是手指接触到模拟发声的整机延迟。
module audio_verify_monitor #(parameter integer CLK_HZ=50000000)(
 input wire clk,rst_n,frame_tick,engine_busy,engine_done,input wire [27:0] keys,voices,
 input wire signed [15:0] pcm,input wire [7:0] faults,input wire [5:0] test_units,
 output wire [191:0] status);
 reg [25:0] second_count;reg [15:0] frame_count,measured_fs,last_cycles,max_cycles,cycles,peak;
 reg [31:0] latency_counter,last_latency;reg latency_armed,latency_valid,rate_valid;
 reg [27:0] previous_keys;reg [7:0] fault_latch;reg [5:0] active_count;
 integer n;reg [5:0] pop;
 always @*begin pop=0;for(integer j=0;j<28;j=j+1)pop=pop+voices[j];end
 wire [15:0] magnitude=pcm[15]?-pcm:pcm;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin second_count<=0;frame_count<=0;measured_fs<=0;last_cycles<=0;max_cycles<=0;cycles<=0;peak<=0;
   latency_counter<=0;last_latency<=0;latency_armed<=0;latency_valid<=0;rate_valid<=0;previous_keys<=0;fault_latch<=0;active_count<=0;end
  else begin
   previous_keys<=keys;fault_latch<=fault_latch|faults;
   if(second_count==CLK_HZ-1)begin measured_fs<=frame_count+frame_tick;frame_count<=0;second_count<=0;rate_valid<=1;end
   else begin second_count<=second_count+1'b1;if(frame_tick)frame_count<=frame_count+1'b1;end
   if(engine_busy)cycles<=cycles+1'b1;
   else cycles<=0;
   if(engine_done)begin last_cycles<=cycles;if(cycles>max_cycles)max_cycles<=cycles;active_count<=pop;end
   if(frame_tick&&magnitude>peak)peak<=magnitude;
   if(previous_keys==0&&keys!=0&&!latency_armed)begin latency_counter<=0;latency_armed<=1;latency_valid<=0;end
   else if(latency_armed)begin
    if(frame_tick&&pcm!=0)begin last_latency<=latency_counter;latency_armed<=0;latency_valid<=1;end
    else if(latency_counter!=32'hffffffff)latency_counter<=latency_counter+1'b1;
   end
  end
 end
 assign status={74'd0,rate_valid,latency_valid,fault_latch,peak,last_latency,max_cycles,last_cycles,measured_fs,active_count,test_units};
endmodule
