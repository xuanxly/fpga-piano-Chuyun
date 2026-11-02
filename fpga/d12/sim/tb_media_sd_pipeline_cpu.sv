`timescale 1ns/1ps
module sdxc_model_play(input wire cs,sck,mosi,output reg miso=1);
 reg [7:0] shift=0,tx=255;integer bit_no=0,cmd_at=0,head=0,tail=0,app=0,multi=0,sector=0,write_mode=0,write_index=0;
 reg [7:0] fixture[0:20897];initial $readmemh("media_sd_stream.hex",fixture);
 reg [7:0] q[0:4095],command[0:5],storage[0:32767],payload[0:513];integer crc16,crc7,arg,c,i,j,v;
 // 卡在下降沿推出下一位，再加入14ns器件/线路延迟；禁止同沿理想零延迟模型掩盖采样错误。
 always @(negedge sck or posedge cs)begin
  if(cs)miso<=1;else miso<=#14 tx[7-bit_no];
 end
 task put(input integer a);begin q[tail%4096]=a;tail=tail+1;end endtask
 task block_data(input integer at,input integer size);begin
  put(255);put(254);crc16=0;
  for(i=0;i<size;i++)begin
   v=at<0?(i==0?64:i==7?3:i==8||i==9?255:0):fixture[(at*512+i)%20898];put(v);crc16=crc16^(v<<8);
   for(j=0;j<8;j++)crc16=((crc16<<1)^((crc16&32768)?16'h1021:0))&65535;
  end put(crc16>>8);put(crc16);
 end endtask
 task receive(input integer a);begin
  if(write_mode!=0)begin
   if(write_index>0)begin
    payload[write_index-1]=a;write_index++;
    if(write_index==515)begin
     crc16=0;for(i=0;i<512;i++)begin storage[sector*512+i]=payload[i];crc16=crc16^(payload[i]<<8);for(j=0;j<8;j++)crc16=((crc16<<1)^((crc16&32768)?16'h1021:0))&65535;end
     if(payload[512]!=(crc16>>8)||payload[513]!=(crc16&255))$fatal(1,"SD write CRC mismatch");
     sector++;write_index=0;put(5);put(0);put(255);if(write_mode==1)write_mode=0;
    end
   end else if(a==253)begin write_mode=0;end
   else if(a==252||a==254)write_index=1;
  end else if(cmd_at>0||(a&192)==64)begin
   if(cmd_at==0&&a==76)begin multi=0;head=tail;end // CMD12 may interrupt next read token.
   command[cmd_at]=a;cmd_at++;
   if(cmd_at==6)begin
    cmd_at=0;c=command[0]&63;arg={command[1],command[2],command[3],command[4]};crc7=0;
    for(i=0;i<5;i++)begin v=command[i];for(j=0;j<8;j++)begin crc7=crc7<<1;if((v^crc7)&128)crc7=crc7^9;v=v<<1;end end
    if(command[5]!=((crc7<<1|1)&255))$fatal(1,"SD command CRC7 mismatch");
    case(c)
     0:put(1);
     8:begin put(1);put(0);put(0);put(1);put(170);end
     55:put(app?0:1);
     41:begin put(app?0:1);app++;end
     58:begin put(0);put(192);put(255);put(128);put(0);end
     9:begin put(0);block_data(-1,16);end
     17,18:begin if(arg>=4096)$fatal(1,"SD address out of range");put(0);sector=arg;block_data(sector,512);sector++;multi=c==18;end
     12:begin put(255);put(0);multi=0;end
     24,25:begin if(arg>=4096)$fatal(1,"SD address out of range");put(0);sector=arg;write_mode=c==25?2:1;end
     default:$fatal(1,"unexpected SD command %0d",c);
    endcase
   end
  end
 end endtask
 always @(posedge cs)begin bit_no=0;tx=255;cmd_at=0;head=0;tail=0;multi=0;write_mode=0;write_index=0;end
 always @(posedge sck)if(!cs)begin
  shift={shift[6:0],mosi};
  if(bit_no==7)begin
   receive(shift);if(head==tail&&multi)begin block_data(sector,512);sector++;end
   tx=head<tail?q[head%4096]:255;if(head<tail)head++;bit_no=0;
  end else bit_no++;
 end
endmodule
module tb_media_sd_pipeline_cpu;
 reg clk=0,rst_n=0;always #10 clk=~clk;integer phase=0;reg sample_tick=0;
 wire [31:0] boot;wire [2175:0] ui;wire signed [15:0] l,r;wire cs,sck,mosi,miso;
 integer heard=0,nonzero=0,minimum=6144,steady_min=6144;
 always @(posedge clk)if(rst_n)begin
  if(phase==1041)begin phase<=0;sample_tick<=1;end else begin phase<=phase+1;sample_tick<=0;end
  if(dut.play_enable&&sample_tick&&!dut.play_pause)begin
   heard++;if(l||r)nonzero++;if(dut.fifo_count<minimum)minimum=dut.fifo_count;
   if(heard<220000&&dut.fifo_count<steady_min)steady_min=dut.fifo_count;
   if(heard%24000==0)$display("SD pipeline heard=%0d FIFO=%0d",heard,dut.fifo_count);
  end
 end
 media_soc #(.FIRMWARE("media_sd_pipeline.hex"))dut(.clk(clk),.rst_n(rst_n),.page(3'd5),.command_valid(1'b0),.command(32'd0),.record_valid(1'b0),.record_pcm(16'd0),.sample_tick(sample_tick),.sd_miso(miso),.sd_cs_n(cs),.sd_sck(sck),.sd_mosi(mosi),.ui_snapshot(ui),.boot_status(boot),.play_l(l),.play_r(r),.pixel_clk(clk),.display_bank(ui[0]),.text_address(6'd0));
 sdxc_model_play card(cs,sck,mosi,miso);
 initial begin #101;rst_n=1;wait(boot==32'hd9b2d00d||boot[31:8]==24'hd9b2ee);#1;
  if(boot!=32'hd9b2d00d)$fatal(1,"SD playback failed boot=%h heard=%0d FIFO=%0d",boot,heard,dut.fifo_count);
  if(heard<245000||nonzero<220000||dut.play_underflow)$fatal(1,"SD playback incomplete");
  $display("PASS media_sd_pipeline_cpu: real CPU + SD driver + SPI/CRC card model + 200 MP3 frames + resampler + realtime stereo FIFO; heard=%0d nonzero=%0d minimum=%0d steady_min=%0d",heard,nonzero,minimum,steady_min);$finish;
 end
 initial begin #8000000000;$fatal(1,"SD pipeline timeout boot=%h",boot);end
endmodule
