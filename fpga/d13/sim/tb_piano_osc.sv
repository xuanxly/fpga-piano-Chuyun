`timescale 1ns/1ps
module tb_piano_osc;
reg clk=0; always #10 clk=~clk;
reg rst_n=0, sample_tick=0, note_start=0;
reg [31:0] phase_step=0;
wire signed [15:0] sample_out;
piano_osc dut(clk, rst_n, sample_tick, note_start, phase_step, sample_out);
integer checks=0;
integer i,k,s1,s2,s3,expected,min_value=0,max_value=0;
reg [31:0] model_phase=0, old_phase;
reg signed [15:0] old_sample;
reg [31:0] steps[0:6];

function integer reference_sine;
input [31:0] phase;
integer quadrant, coord, idx, frac, a,b,mag;
real a_real,b_real;
begin
quadrant=phase[31:30];
coord=phase[29:16];
if(quadrant==1 || quadrant==3) coord=16384-coord;
idx=coord/1024; frac=coord%1024;
a_real=$sin(3.14159265358979323846*idx/32.0)*32767.0;
if(idx>=16) b_real=32767.0;
else b_real=$sin(3.14159265358979323846*(idx+1)/32.0)*32767.0;
a=$rtoi(a_real+0.5); b=$rtoi(b_real+0.5);
mag=a+((b-a)*frac)/1024;
if(quadrant>=2) reference_sine=-mag;
else reference_sine=mag;
end endfunction

task step;
input integer tick, restart;
input [31:0] increment;
begin
@(negedge clk);
sample_tick=tick;note_start=restart;phase_step=increment;
if(restart) begin model_phase=0;expected=0;end
else if(tick) begin
s1=reference_sine(model_phase);
s2=reference_sine(model_phase*32'd2);
s3=reference_sine(model_phase*32'd3);
expected=(s1>>>1)+(s2>>>3)+(s3>>>4);
model_phase=model_phase+increment;
end else expected=sample_out;
@(posedge clk); #1;
checks=checks+1;
if(sample_out !== expected[15:0]) $fatal(1,"sample mismatch phase=%h got=%d expected=%d",model_phase,sample_out,expected);
if(dut.phase_acc !== model_phase) $fatal(1,"phase continuity mismatch");
if(sample_out>max_value) max_value=sample_out;
if(sample_out<min_value) min_value=sample_out;
if(sample_out>22527 || sample_out < -22529) $fatal(1,"output range");
@(negedge clk);sample_tick=0;note_start=0;
repeat(2) @(posedge clk); #1; // 插值流水级需要空闲时钟；保留每个样本的数学参考比较
end endtask

initial begin
steps[0]=32'd0;steps[1]=32'd23409859;steps[2]=32'd44008158;
steps[3]=32'hffffffff;steps[4]=32'h40000000;
steps[5]=32'h80000000;steps[6]=32'h01000000;
#31;
if(sample_out!==16'sd0 || dut.phase_acc!==0) $fatal(1,"reset failure");
@(negedge clk);rst_n=1;
for(k=0;k<7;k=k+1) begin
step(0,1,steps[k]);
for(i=0;i<2048;i=i+1) begin
step(1,0,steps[k]);
if((i%127)==0) step(0,0,steps[k]);
end
end
for(i=0;i<8192;i=i+1) step(1,0,32'h00080000); // all fine positions through four quadrants
for(i=0;i<1000;i=i+1) step(1,0,$urandom);
step(1,1,32'd23409859); // restart must override simultaneous sample tick
step(1,0,32'd23409859);
step(0,1,32'd44008158); // one-clock pulse outside tick must be captured
step(1,0,32'd44008158);
@(negedge clk);rst_n=0;#1;
if(sample_out!==0 || dut.phase_acc!==0) $fatal(1,"async reset failure");
$display("PASS piano_osc checks=%0d range=[%0d,%0d]",checks,min_value,max_value);
$finish;
end
endmodule
