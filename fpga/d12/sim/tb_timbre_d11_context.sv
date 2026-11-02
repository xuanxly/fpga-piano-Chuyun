`timescale 1ns/1ps
// 新增分布式RAM的隔离检查：交错起音/松键/重按时，28个铃音相位和亮度不串声部。
module tb_timbre_d11_context;
    wire vibrato_enable=0;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,sample_tick=0;reg [27:0] key_gate=0;reg [335:0] key_pressure={28{12'd3072}};
 reg signed [3:0] transpose=0;reg [2:0] timbre_select=1;
 wire signed [15:0] mixed_sample;wire frame_done;wire [27:0] voice_active;wire busy,ready,deadline_fault;
 piano28_timbre_engine dut(.*);
 wire [31:0] steps[0:27];genvar k;
 generate for(k=0;k<28;k++)begin:freq
  note_frequency28 frequency(.key_index(5'(k)),.transpose(4'sd0),.phase_step(steps[k]));
 end endgenerate
 reg [31:0] expected_phase[0:27];reg [23:0] old_brightness[0:27];reg [27:0] prev=0;
 integer n,i,cycles,checks=0;
 task frame;
 begin
  @(negedge clk);sample_tick=1;@(negedge clk);sample_tick=0;cycles=0;
  while(!frame_done)begin @(negedge clk);cycles++;if(cycles>1000)$fatal(1,"late context frame");end
  if(cycles!=896||deadline_fault)$fatal(1,"context scheduling");
 end endtask
 initial begin
  #101;rst_n=1;wait(ready);repeat(270)frame();
  for(i=0;i<28;i++)begin expected_phase[i]=dut.tone_mem[i][63:32];old_brightness[i]=dut.tone_mem[i][31:8];end
  for(n=0;n<2200;n++)begin
   case(n)
    0:key_gate[0]=1;127:key_gate[27]=1;255:key_gate[4]=1;511:key_gate[0]=0;
    640:key_gate[0]=1;1000:key_gate=28'hfffffff;1250:key_gate=0;
   endcase
   for(i=0;i<28;i++)begin
    if(key_gate[i]&&!prev[i])expected_phase[i]=0;
    expected_phase[i]=expected_phase[i]+steps[i]+steps[i]+steps[i]+(steps[i]>>1);
   end
   frame();
   for(i=0;i<28;i++)begin
    if(dut.tone_mem[i][63:32]!==expected_phase[i])$fatal(1,"bell context alias at frame%0d key%0d",n,i);
    if(key_gate[i]&&!prev[i])begin
     if(dut.tone_mem[i][31:8]!==24'hffff00)$fatal(1,"new-note brightness key%0d",i);
    end else if(dut.tone_mem[i][31:8]>old_brightness[i])$fatal(1,"brightness leaked between keys");
    old_brightness[i]=dut.tone_mem[i][31:8];checks++;
   end
   prev=key_gate;
  end
  // 观察实际CLEAR帧，要求新增与原上下文都清零，不能留下旧铃音或小数尾巴。
  timbre_select=3;
  do frame();while(!dut.clear_frame);
  for(i=0;i<28;i++)if(dut.tone_mem[i]!==64'd0||dut.context_mem[i]!==64'd0)$fatal(1,"incomplete tone clear");
  $display("PASS d11_context: %0d independent bell/brightness checks, interleaved notes/retrigger/all28, complete switch clear",checks);$finish;
 end
 initial begin #100000000;$fatal(1,"context timeout");end
endmodule
