`timescale 1ns/1ps
module tb_media_mp3_stereo_cpu_clz;
 reg clk=0,rst_n=0;always #10 clk=~clk;
 reg [2175:0] results=0;wire [2175:0] ui;wire [31:0] boot;reg [31:0] crc[0:5];integer cycles,maximum=0,clock_count=0,started[0:5],measured[0:5];
 always @(posedge clk)begin
 clock_count++;if(dut.write&&dut.offset>=4096&&dut.offset<4096+72)results[(dut.offset-4096)*8+:32]=dut.dout;
 if(dut.write&&dut.offset==88)begin
 if(dut.dout[31:8]==24'hbec000)started[dut.dout[2:0]]=clock_count;
 if(dut.dout[31:8]==24'hbed000)begin measured[dut.dout[2:0]]=clock_count-started[dut.dout[2:0]];$display("Measured decode frame %0d cycles=%0d",dut.dout[2:0],clock_count-started[dut.dout[2:0]]);end
 end end
 media_soc #(.FIRMWARE("media_clz_benchmark_stereo.hex")) dut(.pixel_clk(clk),.display_bank(ui[0]),.text_address(6'd0),.clk(clk),.rst_n(rst_n),.page(3'd0),.command_valid(1'b0),.command(32'd0),.record_valid(1'b0),.record_pcm(16'd0),.sample_tick(1'b0),.sd_miso(1'b1),.ui_snapshot(ui),.boot_status(boot));
 initial begin $readmemh("media_clz_bench_stereo_crc.hex",crc);#101;rst_n=1;wait(boot==32'hd9be0003);#100;
  for(integer i=0;i<3;i++)begin
   if(results[i*96+:32]!=0)$fatal(1,"MP3 target decode error frame %0d %h",i,results[i*96+:32]);
   cycles=measured[i];if(cycles>maximum)maximum=cycles;
   if(results[i*96+64+:32]!==crc[i])$fatal(1,"target/native PCM mismatch frame %0d got=%h expected=%h",i,results[i*96+64+:32],crc[i]);
   $display("MP3 RV32 frame %0d cycles %0d of 1306122 budget CRC=%h",i,cycles,crc[i]);
   if(cycles<1000||cycles>=1000000)$fatal(1,"insufficient realtime margin");
  end
  $display("PASS media_mp3_stereo_cpu: three 320kbps independent stereo noise frames decoded bit-exact against native fixed point; maximum=%0d cycles",maximum);$finish;
 end
 initial begin #200000000;$fatal(1,"benchmark timeout boot=%h",boot);end
endmodule
