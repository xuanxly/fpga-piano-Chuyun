`timescale 1ns/1ps
// 当前发布配置：实际ADC模型+触控快照+CPU媒体系统+新音色引擎+视频/灯光。
module tb_timbre_system;
 reg sys_clk=0;always #10 sys_clk=~sys_clk;
 reg rst_n=0,connected=1,valid=0;reg [4:0] active=0;reg [39:0] ids=0;reg [49:0] xs=0,ys=0;
 wire cs,sck,mosi;wire [3:0] miso;wire [27:0] keys;wire [3:0] page;wire [2:0] fault;wire [6:0] volume;wire pv;
 wire signed [15:0] pcm;
 piano28_touch_system #(.BOOT_CYCLES(10),.ENABLE_MEDIA(1)) dut(.sys_clk(sys_clk),.rst_n(rst_n),.enc_a(1'b1),.enc_b(1'b1),.dark_button_n(1'b1),
  .adc_miso(miso),.touch_connected(connected),.touch_frame_valid(valid),.touch_active(active),.touch_ids(ids),.touch_xs(xs),.touch_ys(ys),
  .adc_cs_n(cs),.adc_sck(sck),.adc_mosi(mosi),.ui_page(page),.ui_volume(volume),.monitor_keys(keys),.monitor_valid(pv),.monitor_pcm(pcm),.audio_fault(fault),.usb_diag(72'd0),.sd_miso(1'b1));
 reg [79:0] values[0:3];wire integer transactions[0:3];genvar b;
 generate for(b=0;b<4;b++)begin:adc mcp3008_model m(cs,sck,mosi,values[b],miso[b],transactions[b]);end endgenerate
 integer i,nonzero=0,frames=0;
 always @(negedge sys_clk)if(dut.sys_reset_n)begin
  if(fault||dut.fft_overrun||dut.u_lights.render_overrun)$fatal(1,"integration deadline fault");
  if(pv)begin frames++;if(pcm!=0)nonzero++;end
 end
 task send;begin @(negedge sys_clk);valid=1;@(negedge sys_clk);valid=0;repeat(5)@(negedge sys_clk);end endtask
 task tap(input integer px,py);begin active=0;send();active=1;ids[7:0]=11;xs[9:0]=px;ys[9:0]=py;send();active=0;send();end endtask
 initial begin
  for(i=0;i<4;i++)values[i]=0;#201;rst_n=1;#2000000;
  values[3][69:60]=700;#12000000;
  if(keys!=28'h8000000||nonzero<200)$fatal(1,"physical B6 startup");
  tap(740,450);tap(96,320);if(page!=6)$fatal(1,"real fifth app route");
  tap(200,300);#6500000;
  if(dut.timbre_selected!=3||dut.u_piano.timbre_engine.u_engine.current_timbre!=3||dut.u_piano.voice_active!=0||pcm!=0)$fatal(1,"selection did not silence held physical key");
  values[3][69:60]=0;#12000000;values[3][69:60]=700;#12000000;
  if(dut.u_piano.voice_active!=28'h8000000||pcm==0)$fatal(1,"physical note did not restart with guitar");
  tap(740,450);tap(268,120);if(page!=2)$fatal(1,"keyboard after timbre selection");
  active=1;ids[7:0]=22;xs[9:0]=20;ys[9:0]=100;send();#3000000;
  if(keys!=28'h8000001||dut.u_piano.voice_active!=28'h8000001)$fatal(1,"touch and physical global timbre");
  connected=0;#3000000;if(keys!=28'h8000000||dut.timbre_selected!=3)$fatal(1,"disconnect corrupted physical/timbre");
  // 本用例50.5ms，48kHz约2424帧；不能错误地要求超过测试时长的2500帧。
  if(frames<2300||nonzero<1000)$fatal(1,"integration coverage frames=%0d nonzero=%0d",frames,nonzero);
  $display("PASS timbre_system: real four ADCs, fifth app, global physical/touch tone, held-key silence, re-press, USB detach, %0d PCM frames",frames);$finish;
 end
 initial begin #100000000;$fatal(1,"integration timeout");end
endmodule
