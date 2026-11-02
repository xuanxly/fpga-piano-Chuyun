`timescale 1ns/1ps
module sdxc_model_d9(input wire cs,sck,mosi,output reg miso=1);
 reg [7:0] shift=0,tx=255;integer bit_no=0,cmd_at=0,head=0,tail=0,app=0,multi=0,sector=0,write_mode=0,write_index=0;
 reg [7:0] q[0:4095],command[0:5],storage[0:32767],payload[0:513];integer crc16,crc7,arg,c,i,j,v;
 // 卡在下降沿推出下一位，再加入14ns器件/线路延迟；禁止同沿理想零延迟模型掩盖采样错误。
 always @(negedge sck or posedge cs)begin
  if(cs)miso<=1;else miso<=#14 tx[7-bit_no];
 end
 task put(input integer a);begin q[tail%4096]=a;tail=tail+1;end endtask
 task block_data(input integer at,input integer size);begin
  put(255);put(254);crc16=0;
  for(i=0;i<size;i++)begin
   v=at<0?(i==0?64:i==7?3:i==8||i==9?255:0):storage[at*512+i];put(v);crc16=crc16^(v<<8);
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
     17,18:begin if(arg>=64)$fatal(1,"SD address out of range");put(0);sector=arg;block_data(sector,512);sector++;multi=c==18;end
     12:begin put(255);put(0);multi=0;end
     24,25:begin if(arg>=64)$fatal(1,"SD address out of range");put(0);sector=arg;write_mode=c==25?2:1;end
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
module tb_media_sd_cpu;
 reg clk=0,rst_n=0;always #10 clk=~clk;wire cs,sck,mosi,miso;wire [31:0] boot;wire [2175:0] ui;
 integer cycles=0,write_at=0,read_at=0,write_cycles=0,read_cycles=0;
 media_soc #(.FIRMWARE("media_sd_cpu.hex"))dut(.clk(clk),.rst_n(rst_n),.page(3'd0),.command_valid(1'b0),.command(32'd0),.record_valid(1'b0),.record_pcm(16'd0),.sample_tick(1'b0),.sd_miso(miso),.sd_cs_n(cs),.sd_sck(sck),.sd_mosi(mosi),.boot_status(boot),.ui_snapshot(ui),.pixel_clk(clk),.display_bank(ui[0]),.text_address(6'd0));
 sdxc_model_d9 card(cs,sck,mosi,miso);
 always @(posedge clk)begin
  cycles++;if(dut.write&&dut.offset==88)case(dut.dout)
   32'hd9c00001:write_at=cycles;
   32'hd9c00002:begin write_cycles=cycles-write_at;read_at=cycles;$display("SD CPU write 2048 bytes cycles=%0d",write_cycles);end
   32'hd9c00003:begin read_cycles=cycles-read_at;$display("SD CPU read 2048 bytes cycles=%0d",read_cycles);end
  endcase
 end
 initial begin #101;rst_n=1;wait(boot==32'hd9c0d00d||boot[31:8]==24'hd9c0ee);#1;
  if(boot!=32'hd9c0d00d)$fatal(1,"actual CPU/SPI SD failed %h",boot);
  if(write_cycles>900000||read_cycles>900000||write_cycles<65536||read_cycles<65536)$fatal(1,"SD payload throughput insufficient");
  $display("PASS media_sd_cpu: actual CPU + production sd_spi.c + SPI RTL + independent bit-level SDXC model; 2048-byte read/write CRC and data; cycles write=%0d read=%0d",write_cycles,read_cycles);$finish;
 end
 initial begin #80000000;$fatal(1,"SD CPU timeout boot=%h cmd=%0d token=%h",boot,card.c,card.tx);end
endmodule
