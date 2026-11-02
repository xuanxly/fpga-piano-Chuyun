`timescale 1ns/1ps
module tb_media_soc_equivalence;
 reg clk=0,rst_n=0;always #10 clk=~clk;
 reg [2:0] page=5;reg command_valid=0,record_valid=0,sample_tick=0;
 reg [31:0] command=0;reg signed [15:0] record_pcm=0;
 wire ex0,ex1;wire signed [15:0] l0,r0,l1,r1;wire [2175:0] ui0,ui1;
 wire nv0,nv1;wire [2:0] np0,np1;wire [31:0] boot0,boot1;wire cs0,ck0,mo0,cs1,ck1,mo1;
 media_soc #(.FIFO_WORDS(12))dut(.clk(clk),.rst_n(rst_n),.page(page),.command_valid(command_valid),.command(command),.record_valid(record_valid),.record_pcm(record_pcm),.sample_tick(sample_tick),
  .sd_miso(1'b1),.sd_cs_n(cs0),.sd_sck(ck0),.sd_mosi(mo0),.playback_exclusive(ex0),.play_l(l0),.play_r(r0),.ui_snapshot(ui0),.nav_valid(nv0),.nav_page(np0),.boot_status(boot0),.pixel_clk(clk),.display_bank(ui0[0]),.text_address(6'd0));
 media_soc_reference #(.FIFO_WORDS(12))refdut(.clk(clk),.rst_n(rst_n),.page(page),.command_valid(command_valid),.command(command),.record_valid(record_valid),.record_pcm(record_pcm),.sample_tick(sample_tick),
  .sd_miso(1'b1),.sd_cs_n(cs1),.sd_sck(ck1),.sd_mosi(mo1),.playback_exclusive(ex1),.play_l(l1),.play_r(r1),.ui_snapshot(ui1),.nav_valid(nv1),.nav_page(np1),.boot_status(boot1),.pixel_clk(clk),.display_bank(ui1[0]),.text_address(6'd0));
 reg bus_cycle=0,bus_write=0;reg [29:0] bus_address=30'h3c000000;reg [31:0] bus_data=0;
 integer seed=32'h06144a18,n,sel,off;reg [31:0] random_word;
 function integer rnd(input integer limit);integer v;begin v=$random(seed)&32'h7fffffff;rnd=v%limit;end endfunction
 initial begin
  force dut.icyc=0;force refdut.icyc=0;
  force dut.dcyc=bus_cycle;force refdut.dcyc=bus_cycle;force dut.dstb=bus_cycle;force refdut.dstb=bus_cycle;
  force dut.dwe=bus_write;force refdut.dwe=bus_write;force dut.dadr=bus_address;force refdut.dadr=bus_address;
  force dut.dout=bus_data;force refdut.dout=bus_data;force dut.dsel=4'hf;force refdut.dsel=4'hf;
  #101;rst_n=1;
  for(n=0;n<120000;n++)begin
   @(negedge clk);record_valid=rnd(2);sample_tick=rnd(2);record_pcm=$random(seed);
   command_valid=rnd(7)==0;command=$random(seed);page=rnd(20)==0?rnd(6):page;
   bus_cycle=rnd(3)!=0;bus_write=rnd(2);sel=rnd(15);random_word=$random(seed);bus_data=random_word;
   case(sel)
    0:begin off=16;bus_write=1;case(rnd(5))0:bus_data=0;1,2:bus_data=1;3:bus_data=3;default:bus_data=4;endcase end
    1:begin off=32;bus_write=1;case(rnd(5))0:bus_data=0;1,2:bus_data=1;3:bus_data=3;default:bus_data=4;endcase end
    2:begin off=40;bus_write=1;end
    3:begin off=24;bus_write=0;end
    4:begin off=20;bus_write=0;end
    5:begin off=36;bus_write=0;end
    6:begin off=28;bus_write=0;end
    7:begin off=44;bus_write=0;end
    8:begin off=48;bus_write=0;end
    9:begin off=8;bus_write=0;end
    10:begin off=12;bus_write=0;end
    11:begin off=60;bus_write=0;end
    12:begin off=64;bus_data=32'h10040;end
    13:begin off=68;end
    default:begin off=72;bus_write=0;end
   endcase
   bus_address=30'h3c000000+(off>>2);
   @(posedge clk);#1;
   if(dut.fifo_has_data!==(dut.fifo_count!=0)||dut.fifo_has_space!==(dut.fifo_count<12))$fatal(1,"registered FIFO flags differ count=%0d",dut.fifo_count);
   if({ex0,l0,r0,nv0,np0,boot0,cs0,ck0,mo0,dut.dack,dut.ddata,dut.fifo_count,dut.captured,dut.played,dut.rec_overflow,dut.play_underflow}!==
      {ex1,l1,r1,nv1,np1,boot1,cs1,ck1,mo1,refdut.dack,refdut.ddata,refdut.fifo_count,refdut.captured,refdut.played,refdut.rec_overflow,refdut.play_underflow})
    $fatal(1,"SoC cycle equivalence failed cycle%0d off%0d count%0d/%0d",n,off,dut.fifo_count,refdut.fifo_count);
  end
  $display("PASS media_soc_equivalence: %0d randomized cycles against original SoC; exact FIFO flags/count, CPU bus ACK/data, record/pause/tail/overflow, playback/sample output, simultaneous arbitration, event queue and SPI",n);$finish;
 end
 initial begin #4000000;$fatal(1,"SoC equivalence timeout");end
endmodule
