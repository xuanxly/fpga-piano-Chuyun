`timescale 1ns/1ps
// Wishbone BFM isolates the production peripheral RTL; separate boot/MP3 benches execute the actual CPU.
module tb_media_fifo;
 reg clk=0,rst_n=0;always #10 clk=~clk;
 reg [3:0] page=0;reg cv=0,rv=0,tick=0;reg [31:0] command=0;reg signed [15:0] pcm=0;
 reg req=0,we=0;reg [29:0] address=0;reg [31:0] data=0;
 wire [31:0] text_data;wire exclusive;wire signed [15:0] l,r;integer checks=0,waits;reg [31:0] q;
 media_soc #(.FIFO_WORDS(12)) dut(.pixel_clk(clk),.display_bank(dut.ui_snapshot[0]),.text_address(6'd0),.text_data(text_data),.clk(clk),.rst_n(rst_n),.page(page),.command_valid(cv),.command(command),.record_valid(rv),.record_pcm(pcm),.sample_tick(tick),.playback_exclusive(exclusive),.play_l(l),.play_r(r),.sd_miso(1'b1));
 task bus(input bit writing,input integer off,input [31:0] value);begin
  @(negedge clk);req=1;we=writing;address=(32'hf0000000+off)>>2;data=value;
  @(posedge clk);#1;waits=0;while(!dut.dack)begin @(posedge clk);#1;waits++;if(waits>8)$fatal(1,"missing ACK");end q=dut.ddata;
  @(negedge clk);req=0;@(posedge clk);#1;checks++;
 end endtask
 task sample(input integer v);begin @(negedge clk);pcm=v;rv=1;@(negedge clk);rv=0;end endtask
 task outsample;begin @(negedge clk);tick=1;@(posedge clk);#1;@(negedge clk);tick=0;end endtask
 task pop(input [31:0] expected,input integer n);begin bus(0,24,0);if(q!==expected)$fatal(1,"FIFO data %h expected %h",q,expected);bus(0,60,0);if(q!=n)$fatal(1,"tail sample count %0d expected %0d",q,n);end endtask
 initial begin
  force dut.icyc=0;force dut.istb=0;force dut.dcyc=req;force dut.dstb=req;force dut.dwe=we;force dut.dadr=address;force dut.dout=data;force dut.dsel=4'hf;
  #101;rst_n=1;bus(1,16,4);bus(1,16,1);
  sample(1);sample(2);sample(3);bus(1,16,3);bus(1,16,1);sample(4);sample(5);
  pop(32'h00020001,2);pop(32'h00000003,1);pop(32'h00050004,2);bus(1,16,0);bus(0,28,0);if(q!=5)$fatal(1,"capture count");
  // Wrap a non-power-of-two production pointer is exercised below with 16 here; actual size 12288 uses same comparator.
  for(integer i=0;i<40;i++)begin bus(1,16,1);sample(i);sample(-i);pop({16'(-i),16'(i)},2);end
  bus(1,16,4);bus(1,16,1);sample(1);sample(2);sample(3);
  fork sample(4);pop(32'h00020001,2);join
  pop(32'h00040003,2);
  bus(1,16,4);bus(1,16,1);for(integer i=0;i<26;i++)sample(i);bus(0,20,0);if(!q[31]||q[13:0]!=12||dut.rec_enable)$fatal(1,"record overflow must stop");
  bus(1,16,4);bus(1,16,1);@(negedge clk);dut.captured=14399998;sample(99);sample(100);sample(101);bus(0,28,0);if(q!=14400000)$fatal(1,"five-minute capture boundary");bus(1,16,0);
  bus(1,32,4);page=5;bus(1,40,32'h00010002);bus(1,32,1);
  fork outsample();bus(1,40,32'h00030004);join
  if(l!=2||r!=1)$fatal(1,"simultaneous playback refill lost old frame");outsample();if(l!=4||r!=3)$fatal(1,"CPU refill was not retried");
  bus(1,32,4);page=5;for(integer i=0;i<12;i++)bus(1,40,{16'(1000+i),16'(-1000-i)});
  bus(1,32,1);if(!exclusive)$fatal(1,"missing playback exclusivity");
  for(integer i=0;i<12;i++)begin outsample();if(l!==-1000-i||r!==1000+i)$fatal(1,"stereo order %0d L%0d R%0d",i,l,r);end
  outsample();bus(0,48,0);if(q!=1||l||r)$fatal(1,"underflow must output silence and flag");
  bus(1,32,4);bus(1,40,32'h1234fedc);bus(1,32,3);outsample();if(dut.fifo_count!=1||l||r)$fatal(1,"paused playback consumed data");
  bus(1,32,1);page=0;#1;if(exclusive)$fatal(1,"exit page did not immediately restore synth");outsample();if(dut.fifo_count!=1)$fatal(1,"background playback");
  for(integer i=0;i<16;i++)begin @(negedge clk);cv=1;command=32'h02000000+i;@(negedge clk);cv=0;end
  bus(0,8,0);if(q[4:0]!=16)$fatal(1,"event queue count");
  for(integer i=0;i<16;i++)begin bus(0,12,0);if(q!=32'h02000000+i)$fatal(1,"event order");end
  bus(1,4096,32'hABCD1234);bus(1,4352,32'h10203040);bus(1,84,1);repeat(4)@(posedge clk);#1;
  if(dut.ui_snapshot[2079:2048]!=32'h10203040||text_data!=32'hABCD1234)$fatal(1,"atomic UI/text bank commit");
  $display("PASS media_fifo: %0d bus operations, packed/tail samples, immediate resume, wrap, overflow, 5min boundary, stereo/pause/exit, events/UI",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"FIFO test timeout");end
endmodule
