`timescale 1ns/1ps
// 从CPU原始Wishbone端驱动真实SoC，验证新增流水边界、字节选择和一次性副作用。
module tb_d12_wishbone;
 reg clk=0;always #10 clk=~clk;reg rst_n=0;reg [3:0] page=7;
 reg command_valid=0;reg [31:0] command=0;reg record_valid=0;reg signed [15:0] record_pcm=0;reg sample_tick=0;
 wire [2175:0] ui_snapshot;wire [31:0] boot_status;wire playback_exclusive;wire signed [15:0] play_l,play_r;
 reg cyc=0,stb=0,we=0;reg [29:0] adr=0;reg [31:0] wd=0;reg [3:0] sel=15;
 media_soc d(.clk(clk),.rst_n(rst_n),.page(page),.keys(28'd0),.command_valid(command_valid),.command(command),
  .record_valid(record_valid),.record_pcm(record_pcm),.sample_tick(sample_tick),.sd_miso(1'b1),
  .ch_ready(1'b0),.ch_rx_req(1'b0),.ch_tx_ack(1'b0),.ch_rx_data(4'd0),.pixel_clk(clk),.display_bank(ui_snapshot[0]),.text_address(6'd0),
  .ui_snapshot(ui_snapshot),.boot_status(boot_status),.playback_exclusive(playback_exclusive),.play_l(play_l),.play_r(play_r));
 integer writes=0,expected_writes=0,transactions=0,arbitration_stalls=0;
 always @(posedge clk)if(rst_n&&d.audio_wait&&d.base_request)arbitration_stalls++;
 always @(posedge clk)if(rst_n&&d.write)writes++;
 task bus(input bit wr,input [31:0] ba,data,input [3:0] bytes,output [31:0] result);
 integer waited;
 begin
  @(negedge clk);cyc=1;stb=1;we=wr;adr=ba>>2;wd=data;sel=bytes;waited=0;
  do begin @(negedge clk);waited++;if(waited>20)$fatal(1,"Wishbone timeout addr%h",ba);end while(!d.dack);
  result=d.ddata;transactions++;if(wr&&ba[31:28]==15)expected_writes++;
  cyc=0;stb=0;repeat(3)@(negedge clk);
  if(writes!=expected_writes)$fatal(1,"Duplicate/missing MMIO side effect got%0d expected%0d",writes,expected_writes);
 end endtask
 task put(input [31:0] ba,data);reg [31:0] ignore;begin bus(1,ba,data,15,ignore);end endtask
 task sample(input signed [15:0] value);begin @(negedge clk);record_pcm=value;record_valid=1;@(negedge clk);record_valid=0;end endtask
 task tick(input [31:0] expected);begin @(negedge clk);sample_tick=1;@(negedge clk);sample_tick=0;if({play_r,play_l}!==expected)$fatal(1,"Playback RAM mismatch %h expected%h",{play_r,play_l},expected);end endtask
 task burst(input bit wr,input [31:0] ba,data,output [31:0] result);
 integer waited;begin
  @(negedge clk);while(d.dack)@(negedge clk);cyc=1;stb=1;we=wr;adr=ba>>2;wd=data;sel=15;waited=0;
  do begin @(negedge clk);waited++;if(waited>20)$fatal(1,"Burst timeout");end while(!d.dack);
  result=d.ddata;transactions++;if(wr&&ba[31:28]==15)expected_writes++;
 end endtask
 reg [31:0] reference_rom[0:10239],ram_model[0:31],rd,value,seed=32'h78a91cb2;integer idx,mask;
 function [31:0] rnd;begin seed=seed^(seed<<13);seed=seed^(seed>>17);seed=seed^(seed<<5);rnd=seed;end endfunction
 initial begin
  force d.dcyc=cyc;force d.dstb=stb;force d.cpu_dwe=we;force d.cpu_dadr=adr;force d.cpu_dout=wd;force d.cpu_dsel=sel;
  force d.icyc=0;force d.istb=0;$readmemh("rom/media_firmware.hex",reference_rom);
  repeat(4)@(negedge clk);rst_n=1;
  for(integer k=0;k<128;k++)begin idx=rnd()%10240;bus(0,idx*4,0,15,rd);if(rd!==reference_rom[idx])$fatal(1,"Data ROM read%0d %h expected%h",idx,rd,reference_rom[idx]);end
  for(integer k=0;k<32;k++)begin ram_model[k]=rnd();put(32'h10000000+k*4,ram_model[k]);end
  for(integer k=0;k<512;k++)begin
   idx=rnd()%32;mask=rnd()%16;value=rnd();bus(1,32'h10000000+idx*4,value,mask,rd);
   for(integer j=0;j<4;j++)if(mask[j])ram_model[idx][j*8+:8]=value[j*8+:8];
   bus(0,32'h10000000+idx*4,0,15,rd);if(rd!==ram_model[idx])$fatal(1,"RAM byte-write mismatch%0d got%h expected%h",idx,rd,ram_model[idx]);
  end
  // CYC/STB持续保持时，游戏写后立即读仍必须看到新状态，不能重放写命令。
  for(integer j=0;j<3;j++)begin
   burst(1,32'hf0000100,j==1?11:9,rd);burst(0,32'hf0000100,0,rd);
   if(rd[2:0]!==((j==1)?3'b111:3'b101))$fatal(1,"Game ordered write/read%h",rd);
  end
  cyc=0;stb=0;repeat(3)@(negedge clk);if(writes!=expected_writes)$fatal(1,"Burst duplicated MMIO writes");put(32'hf0000100,12);
  put(32'hf0000058,32'h1234abcd);bus(0,32'hf0000058,0,15,rd);if(rd!==32'h1234abcd)$fatal(1,"Boot status write/read");
  for(integer k=0;k<4;k++)begin @(negedge clk);command=32'hab000000|k;command_valid=1;@(negedge clk);command_valid=0;end
  bus(0,32'hf0000008,0,15,rd);if(rd[4:0]!=4)$fatal(1,"Event queue count");
  for(integer k=0;k<4;k++)begin bus(0,32'hf000000c,0,15,rd);if(rd!==(32'hab000000|k))$fatal(1,"Event FIFO ordering/duplicate pop");end
  put(32'hf0000010,4);put(32'hf0000010,1);sample(16'h1111);sample(16'h2222);sample(16'h3333);sample(16'h4444);put(32'hf0000010,0);
  bus(0,32'hf0000014,0,15,rd);if(rd[13:0]!=2)$fatal(1,"Record FIFO count%h",rd);
  bus(0,32'hf0000018,0,15,rd);if(rd!==32'h22221111)$fatal(1,"Recorded pair0%h",rd);
  bus(0,32'hf0000018,0,15,rd);if(rd!==32'h44443333)$fatal(1,"Recorded pair1%h",rd);
  // 第四个录音采样与CPU读同拍：SP音频RAM先接收采样，CPU等待后再读，不能丢/重排。
  put(32'hf0000010,4);put(32'hf0000010,1);sample(16'h5555);sample(16'h6666);sample(16'h7777);
  fork
   bus(0,32'hf0000018,0,15,rd);
   begin wait(d.data_pending&&!d.dack);@(negedge clk);record_pcm=16'h8888;record_valid=1;@(negedge clk);record_valid=0;end
  join
  if(rd!==32'h66665555)$fatal(1,"Contended record pair0%h",rd);
  bus(0,32'hf0000018,0,15,rd);if(rd!==32'h88887777)$fatal(1,"Contended record pair1%h",rd);put(32'hf0000010,0);
  // 缩短仿真时间，仅预置累计计数到最后两采样；实际采样、FIFO和边界逻辑仍运行真实RTL。
  put(32'hf0000010,4);put(32'hf0000010,1);@(negedge clk);d.captured=32'd14399998;d.capture_room=1;
  sample(16'h1234);sample(16'h5678);sample(16'h7fff);sample(16'h7fff);
  bus(0,32'hf000001c,0,15,rd);if(rd!==32'd14400000||d.capture_room)$fatal(1,"Five-minute capture boundary%0d",rd);
  bus(0,32'hf0000018,0,15,rd);if(rd!==32'h56781234)$fatal(1,"Five-minute final pair%h",rd);put(32'hf0000010,0);
  page=5;put(32'hf0000020,4);put(32'hf0000028,32'h44443333);put(32'hf0000028,32'h66665555);put(32'hf0000020,1);
  tick(32'h44443333);tick(32'h66665555);
  // 播放读与CPU写同拍：先读旧立体声帧，再接受CPU新帧，写请求只执行一次。
  put(32'hf0000028,32'haaaabbbb);
  fork
   bus(1,32'hf0000028,32'hccccdddd,15,rd);
   begin wait(d.data_pending&&!d.dack);@(negedge clk);sample_tick=1;@(negedge clk);sample_tick=0;
    if({play_r,play_l}!==32'haaaabbbb)$fatal(1,"Contended playback frame0%h",{play_r,play_l});end
  join
  tick(32'hccccdddd);if(arbitration_stalls<2)$fatal(1,"Audio contention was not exercised");page=0;repeat(2)@(negedge clk);if(playback_exclusive)$fatal(1,"Home left playback exclusive");
  $display("PASS D12 Wishbone %0d transactions:latched request,128 ROM reads,512 byte-mask RAM pairs,exactly-once MMIO,FIFO event order,record/play RAM with actual arbitration stalls,5min boundary,Home stop",transactions);$finish;
 end
 initial begin #10000000;$fatal(1,"Wishbone test timeout");end
endmodule
