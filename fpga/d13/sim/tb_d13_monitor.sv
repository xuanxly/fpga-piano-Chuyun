`timescale 1ns/1ps
module tb_d13_monitor;
 reg clk=0,rst_n=0,frame_tick=0,engine_busy=0,engine_done=0;always #5 clk=~clk;
 reg [27:0] keys=0,voices=0;reg signed [15:0] pcm=0;reg [7:0] faults=0;reg [5:0] test_units=32;wire [191:0] status;
 audio_verify_monitor #(.CLK_HZ(1000)) dut(.*);wire [199:0] digits;reg start=0;
 validation_decimal_formatter fmt(.clk(clk),.rst_n(rst_n),.start(start),.status(status),.digits(digits));
 initial begin #21;rst_n=1;
  for(integer i=0;i<1100;i++)begin @(negedge clk);frame_tick=(i%20)==0;engine_busy=(i%20)<10;engine_done=(i%20)==10;if(i==100)begin keys=1;voices=1;end if(i==130)pcm=-12345;end
  @(negedge clk);frame_tick=0;engine_busy=0;engine_done=0;
  if(status[27:12]!=50||!status[117]||!status[116]||status[107:92]!=12345||status[59:44]!=10)$fatal(1,"monitor measured fields%h",status);
  start=1;@(negedge clk);start=0;repeat(165)@(negedge clk);
  if(digits[39:0]!==40'h0000000050||digits[79:40]!==40'h0000000010||digits[199:160]!==40'h0000012345)$fatal(1,"BCD fields%h",digits);
  faults=8'h84;@(negedge clk);faults=0;@(negedge clk);if(status[115:108]!=8'h84)$fatal(1,"fault latching");
  $display("PASS D13 counters and sequential BCD: observed sample rate, frame cycles, digital trigger latency, peak, fault latch and decimal values");$finish;
 end
endmodule
