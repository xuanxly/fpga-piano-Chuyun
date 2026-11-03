`timescale 1ns/1ps
module tb_d12_volume_pipeline;
 reg clk=0;always #5 clk=~clk;reg rst_n=0,sv=0;reg [298:0] snapshot=0;reg [9:0] x=0,y=0;
 wire [23:0] a,b;wire ha,hb,va,vb,da,db;
 piano_ui_renderer n(.clk(clk),.rst_n(rst_n),.frame_tick(1'b0),.snapshot_valid(sv),.snapshot(snapshot),.x(x),.y(y),.hs(1'b1),.vs(1'b0),.de(1'b1),.rgb(a),.hs_out(ha),.vs_out(va),.de_out(da),.usb_diag(72'd0));
 d12_base_volume_reference o(.clk(clk),.rst_n(rst_n),.frame_tick(1'b0),.snapshot_valid(sv),.snapshot(snapshot),.x(x),.y(y),.hs(1'b1),.vs(1'b0),.de(1'b1),.rgb(b),.hs_out(hb),.vs_out(vb),.de_out(db),.usb_diag(72'd0));
 integer pixels=0;
 task check(input integer px,py);begin @(negedge clk);x=px;y=py;repeat(2)@(posedge clk);#1;
 if({a,ha,va,da}!={b,hb,vb,db})$fatal(1,"Volume pixel mismatch vol%0d x%0d y%0d rgb%h/%h",snapshot[297:291],px,py,a,b);pixels++;end endtask
 initial begin
 repeat(4)@(negedge clk);rst_n=1;
 for(integer v=0;v<128;v++)begin
  @(negedge clk);sv=1;snapshot[297:291]=v;snapshot[290:289]=1;@(negedge clk);sv=0;
  if(n.volume_height!==(v*336/100))$fatal(1,"Height LUT mismatch%0d",v);
  for(integer py=60;py<406;py++)begin check(715,py);check(740,py);end
  for(integer py=410;py<428;py++)for(integer px=710;px<756;px++)check(px,py);
 end
 $display("PASS D12 volume pipeline:all128 snapshot volumes,%0d exact bar/edge/digit pixels,unchangedtwo-cycle sync",pixels);$finish;
 end
 initial begin #100000000;$fatal(1,"Volume pipeline timeout");end
endmodule
