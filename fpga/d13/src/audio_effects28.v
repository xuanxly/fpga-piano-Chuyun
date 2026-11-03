`timescale 1ns/1ps
// 三种纯HDL效果：128ms回声、四梳状+全通混响、分数延时合唱。
// 15个1024x16银行共享一个读写端口；26拍处理一采样，避免多读口复制RAM。
module audio_effects28(input wire clk,rst_n,sample_valid,input wire signed [15:0] sample_in,
 input wire [2:0] enabled,input wire [6:0] reverb_level,echo_level,chorus_level,
 output reg signed [15:0] sample_out,output reg out_valid,ready,busy,fault,output reg clipped);
 localparam integer BANKS=15,WORDS=15360;
 localparam [13:0] C0_BASE=6144,C1_BASE=7643,C2_BASE=9244,C3_BASE=10991,AP_BASE=12858,CH_BASE=13081;
 reg [13:0] init_index;reg [12:0] echo_pos;
 reg [10:0] p0,p1,p2,p3,chorus_pos,chorus_addr;reg [7:0] ap_pos,frac;
 reg [5:0] state;reg [6:0] gl0,gl1,gl2;
 reg signed [15:0] dry,eq,c0q,c1q,c2q,c3q,aq,ca,cb,reverb_wet,chorus_wet,ap_write,echo_write;
 reg signed [17:0] comb_sum;reg signed [31:0] product;reg signed [20:0] mixed;
 reg [31:0] lfo;wire [16:0] triangle=lfo[31]?~lfo[30:14]:lfo[30:14];
 wire [26:0] delay_q16=(27'd512<<16)+({10'd0,triangle}<<9);
 function signed [15:0] sat(input signed [31:0] n);
  begin sat=n>32767?16'sh7fff:n< -32768?16'sh8000:n[15:0];end
 endfunction
 // 向零衰减，防止负一LSB经算术右移永久保留。
 function signed [31:0] decay(input signed [31:0] n,input integer bits);
  begin decay=n<0?-((-n)>>>bits):(n>>>bits);end
 endfunction
 reg mem_enable,mem_write;reg [13:0] mem_address;reg signed [15:0] mem_data;
 // 各延迟线占用互不重叠的地址。所有读写逐拍安排，波形及延迟长度保持。
 always @*begin
  mem_enable=1;mem_write=0;mem_address=0;mem_data=0;
  case(state)
   1:mem_address={1'b0,echo_pos};
   2:mem_address=C0_BASE+{3'd0,p0};
   3:mem_address=C1_BASE+{3'd0,p1};
   4:mem_address=C2_BASE+{3'd0,p2};
   5:mem_address=C3_BASE+{3'd0,p3};
   6:mem_address=AP_BASE+{6'd0,ap_pos};
   7:mem_address=CH_BASE+{3'd0,chorus_addr};
   8:mem_address=CH_BASE+{3'd0,(chorus_addr-11'd1)};
   12:begin mem_write=1;mem_address={1'b0,echo_pos};mem_data=echo_write;end
   13:begin mem_write=1;mem_address=C0_BASE+{3'd0,p0};mem_data=sat(decay(dry,2)+decay($signed(c0q)*3,2));end
   14:begin mem_write=1;mem_address=C1_BASE+{3'd0,p1};mem_data=sat(decay(dry,2)+decay($signed(c1q)*3,2));end
   15:begin mem_write=1;mem_address=C2_BASE+{3'd0,p2};mem_data=sat(decay(dry,2)+decay($signed(c2q)*3,2));end
   16:begin mem_write=1;mem_address=C3_BASE+{3'd0,p3};mem_data=sat(decay(dry,2)+decay($signed(c3q)*3,2));end
   17:begin mem_write=1;mem_address=AP_BASE+{6'd0,ap_pos};mem_data=ap_write;end
   18:begin mem_write=1;mem_address=CH_BASE+{3'd0,chorus_pos};mem_data=dry;end
   default:mem_enable=0;
  endcase
 end
 wire [15:0] bank_value[0:BANKS-1];reg [3:0] read_bank;
 wire signed [15:0] mem_q=bank_value[read_bank];
 always @(posedge clk or negedge rst_n)
  if(!rst_n)read_bank<=0;else if(ready&&mem_enable&&!mem_write)read_bank<=mem_address[13:10];
 genvar b;
 generate for(b=0;b<BANKS;b=b+1)begin:banks
  (* syn_ramstyle="block_ram" *)reg [15:0] mem[0:1023];reg [15:0] value;
  always @(posedge clk)begin
   if(!ready)begin
    if(init_index[13:10]==b)mem[init_index[9:0]]<=0;
   end else if(mem_enable&&mem_address[13:10]==b)begin
    if(mem_write)mem[mem_address[9:0]]<=mem_data;
    else value<=mem[mem_address[9:0]];
   end
  end
  assign bank_value[b]=value;
 end endgenerate
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   ready<=0;init_index<=0;state<=0;busy<=0;fault<=0;clipped<=0;out_valid<=0;sample_out<=0;
   echo_pos<=0;p0<=0;p1<=0;p2<=0;p3<=0;ap_pos<=0;chorus_pos<=0;chorus_addr<=0;frac<=0;lfo<=0;
   dry<=0;eq<=0;c0q<=0;c1q<=0;c2q<=0;c3q<=0;aq<=0;ca<=0;cb<=0;reverb_wet<=0;chorus_wet<=0;
   gl0<=0;gl1<=0;gl2<=0;product<=0;mixed<=0;comb_sum<=0;ap_write<=0;echo_write<=0;
  end else begin
   out_valid<=0;
   if(!ready)begin
    if(init_index==WORDS-1)ready<=1;else init_index<=init_index+1'b1;
    if(sample_valid)begin sample_out<=sample_in;out_valid<=1;end // 初始化期间直通，不中断音频帧。
   end else if(sample_valid&&!busy)begin
    dry<=sample_in;
    // 每采样平滑移动一档，滑条或开关不产生满幅系数跳变。
    if(gl0<(enabled[0]?reverb_level:0))gl0<=gl0+1'b1;else if(gl0>(enabled[0]?reverb_level:0))gl0<=gl0-1'b1;
    if(gl1<(enabled[1]?echo_level:0))gl1<=gl1+1'b1;else if(gl1>(enabled[1]?echo_level:0))gl1<=gl1-1'b1;
    if(gl2<(enabled[2]?chorus_level:0))gl2<=gl2+1'b1;else if(gl2>(enabled[2]?chorus_level:0))gl2<=gl2-1'b1;
    chorus_addr<=chorus_pos-delay_q16[26:16];frac<=delay_q16[15:8];lfo<=lfo+32'd71583;
    state<=1;busy<=1;
   end else if(busy)begin
    if(sample_valid)fault<=1;
    state<=state+1'b1;
    case(state)
     2:eq<=mem_q;
     3:c0q<=mem_q;
     4:c1q<=mem_q;
     5:c2q<=mem_q;
     6:c3q<=mem_q;
     7:aq<=mem_q;
     8:ca<=mem_q;
     9:begin cb<=mem_q;comb_sum<=($signed(c0q)>>>2)+($signed(c1q)>>>2)+($signed(c2q)>>>2)+($signed(c3q)>>>2);
      echo_write<=sat(decay(dry,1)+decay(eq,1));end
     10:begin ap_write<=sat($signed(comb_sum)+decay(aq,1));product<=($signed(cb)-$signed(ca))*$signed({1'b0,frac});end
     11:begin reverb_wet<=sat($signed(aq)-($signed(ap_write)>>>1));chorus_wet<=sat($signed(ca)+(product>>>8));end
     19:mixed<=dry;
     20:product<=reverb_wet*$signed({1'b0,gl0});
     21:mixed<=mixed+(product>>>8);
     22:product<=eq*$signed({1'b0,gl1});
     23:mixed<=mixed+(product>>>7);
     24:product<=chorus_wet*$signed({1'b0,gl2});
     25:mixed<=mixed+(product>>>8);
     26:begin sample_out<=sat(mixed);out_valid<=1;clipped<=(mixed>32767||mixed< -32768);busy<=0;state<=0;
      echo_pos<=(echo_pos==6143)?13'd0:echo_pos+1'b1;
      p0<=(p0==1498)?11'd0:p0+1'b1;p1<=(p1==1600)?11'd0:p1+1'b1;
      p2<=(p2==1746)?11'd0:p2+1'b1;p3<=(p3==1866)?11'd0:p3+1'b1;
      ap_pos<=(ap_pos==222)?8'd0:ap_pos+1'b1;chorus_pos<=chorus_pos+1'b1;
     end
     default:begin end
    endcase
   end
  end
 end
endmodule
