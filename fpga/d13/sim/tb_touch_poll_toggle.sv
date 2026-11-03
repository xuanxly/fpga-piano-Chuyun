`timescale 1ns/1ps
// 单测USB事务结果到HID主机的边界；物理USB枚举/CRC由实际引脚模型另行回归。
module tb_touch_poll_toggle;
 reg clk=0,rst_n=0;always #5 clk=~clk;
 wire dp_o,dm_o,oe,connected,report_valid;wire [87:0] report_data;wire [3:0] fault;wire [7:0] debug_state;wire [63:0] debug_info;
 ws170120_usb_host d(.clk(clk),.rst_n(rst_n),.dp_i(1'b1),.dm_i(1'b0),.dp_o(dp_o),.dm_o(dm_o),.oe(oe),
  .connected(connected),.report_valid(report_valid),.report_data(report_data),.fault(fault),.debug_state(debug_state),.debug_info(debug_info));
 reg [2:0] r;reg [6:0] length;reg toggle;reg [511:0] payload=88'h0100010064006405070101;
 task response(input integer result_value,len,t);begin
  @(negedge clk);r=result_value;length=len;toggle=t;
  force d.state=8'd21;force d.tr_done=1'b1;force d.result=r;force d.in_length=length;force d.in_toggle=toggle;force d.in_data=payload;
  @(posedge clk);#1;
 end endtask
 task finish_response;begin
  @(negedge clk);release d.state;release d.tr_done;release d.result;release d.in_length;release d.in_toggle;release d.in_data;
 end endtask
 initial begin #21;rst_n=1;@(negedge clk);force d.state=8'd21;d.connected=1'b1;
  response(0,0,0);if(d.poll_toggle!=1||report_valid)$fatal(1,"ACKed ZLP did not advance USB toggle");finish_response();
  response(0,11,1);if(!report_valid||d.poll_toggle!=0)$fatal(1,"first real report after ZLP lost");finish_response();
  for(integer i=0;i<16;i++)begin response(0,0,i%2);if(!connected)$fatal(1,"idle ZLP caused re-enumeration");finish_response();end
  response(0,5,0);if(d.poll_toggle!=1||report_valid)$fatal(1,"ACKed short payload toggle");finish_response();
  response(0,11,1);if(!report_valid)$fatal(1,"report after short payload discarded");finish_response();
  response(0,11,1);if(report_valid||d.poll_toggle!=0)$fatal(1,"duplicate DATA republished");finish_response();
  response(1,0,0);if(!connected||d.poll_toggle!=0)$fatal(1,"NAK changed toggle");finish_response();
  $display("PASS touch USB decision: ACKed ZLP/short packet keep toggle sync and connection, next report accepted, duplicate and NAK ignored");$finish;
 end
endmodule
