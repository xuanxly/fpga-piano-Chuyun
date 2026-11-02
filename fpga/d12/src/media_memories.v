`timescale 1ns/1ps
// 按物理BSRAM深度分银行，避免综合器把非2次幂容量补齐成更大的RAM。
// 所有读口均为一拍同步读；只复位选择器，不复位整个存储阵列。
module media_rom #(parameter WORDS=19456,parameter FIRMWARE="rom/media_firmware.hex")(
 input wire clk,input wire enable,input wire [14:0] address,output wire [31:0] q);
 localparam BANKS=WORDS/512;
 wire [BANKS-1:0] columns[0:31];
 genvar b;generate for(b=0;b<BANKS;b=b+1)begin:banks
  localparam [7:0] TENS=8'd48+b/10,ONES=8'd48+b%10;
  localparam FILE={FIRMWARE,".b",TENS,ONES};
  (* syn_keep=1 *)reg selected;
  always @(posedge clk)if(enable)selected<=address[14:9]==b;
  wire [31:0] bank_value;
  if(b<4)begin:lut_rom
   // 8KB代码用LUT ROM，其余固件、工作RAM和音频环形缓冲使用BSRAM。
   (* syn_romstyle="distributed_rom" *) reg [31:0] mem[0:511];
   (* syn_keep=1 *)reg [8:0] held_address;
   initial $readmemh(FILE,mem);
   // 每个银行保留自己的地址寄存器，把每位七千余负载分成局部扇出。
   always @(posedge clk)if(enable&&address[14:9]==b)held_address<=address[8:0];
   assign bank_value=mem[held_address];
  end else begin:block_rom
   (* syn_romstyle="block_rom" *) reg [31:0] mem[0:511];reg [31:0] value;
   initial $readmemh(FILE,mem);
   always @(posedge clk)if(enable&&address[14:9]==b)value<=mem[address[8:0]];
   assign bank_value=value;
  end
  for(genvar lane=0;lane<32;lane=lane+1)begin:bits
   assign columns[lane][b]=selected&&bank_value[lane];
  end
 end endgenerate
 generate for(genvar lane=0;lane<32;lane=lane+1)begin:result_bits
  assign q[lane]=|columns[lane]; // 并行归约，避免全局二进制选择信号驱动整片ROM。
 end endgenerate
endmodule
module media_ram #(parameter WORDS=12288)(input wire clk,enable,write,input wire [13:0] address,
 input wire [31:0] data,input wire [3:0] bytes,output wire [31:0] q);
 localparam BANKS=WORDS/2048;
 wire [31:0] bank_q[0:BANKS-1];reg [2:0] selected;
 always @(posedge clk)if(enable)selected<=address[13:11];
 genvar b,l;generate for(b=0;b<BANKS;b=b+1)begin:banks
  for(l=0;l<4;l=l+1)begin:lanes
   (* syn_ramstyle="block_ram" *) reg [7:0] mem[0:2047];reg [7:0] value;
   always @(posedge clk)begin
    if(enable&&address[13:11]==b)begin
     if(!write)value<=mem[address[10:0]];
     if(write&&bytes[l])mem[address[10:0]]<=data[l*8+:8];
    end
   end
   assign bank_q[b][l*8+:8]=value;
  end
 end endgenerate
 assign q=selected<BANKS?bank_q[selected]:32'd0;
endmodule
module media_audio_ram #(parameter WORDS=12288)(input wire clk,write,read,
 input wire [13:0] waddr,raddr,input wire [33:0] data,output wire [33:0] q);
 localparam BANKS=(WORDS+511)/512;
 wire [33:0] bank_q[0:BANKS-1];reg [4:0] selected;
 always @(posedge clk)if(read)selected<=raddr[13:9];
 genvar b;generate for(b=0;b<BANKS;b=b+1)begin:banks
  (* syn_ramstyle="block_ram" *) reg [33:0] mem[0:511];reg [33:0] value;
  wire en=(write&&waddr[13:9]==b)||(!write&&read&&raddr[13:9]==b);
  wire [8:0] address=write?waddr[8:0]:raddr[8:0];
  always @(posedge clk)begin
   // 音频采样每约1042拍才发生一次；仲裁器使其与CPU访问错开，使用一个32位SP口。
   if(en)begin
    if(write)mem[address]<=data;
    else value<=mem[address];
   end
  end
  assign bank_q[b]=value;
 end endgenerate
 assign q=selected<BANKS?bank_q[selected]:34'd0;
endmodule

// 双缓冲文本：CPU只写不可见银行，像素域在帧边界采用银行指针；每字32位，一拍同步读。
module media_text_ram(input wire cpu_clk,write,input wire [6:0] waddr,input wire [31:0] data,
 input wire pixel_clk,input wire [6:0] raddr,output reg [31:0] q);
 (* syn_ramstyle="block_ram" *) reg [31:0] mem[0:127];integer i;
 initial for(i=0;i<128;i=i+1)mem[i]=32'h20202020;
 always @(posedge cpu_clk)if(write)mem[waddr]<=data;
 always @(posedge pixel_clk)q<=mem[raddr];
endmodule
