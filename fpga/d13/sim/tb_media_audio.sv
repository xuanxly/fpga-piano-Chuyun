`timescale 1ns/1ps
module tb_media_audio;
 reg clk=0,rst_n=0,exclusive=0;always #10 clk=~clk;
 wire rv0,rv1;wire signed [15:0] rec0,rec1;wire [2:0] fault0,fault1;integer samples=0,nonzero=0,serial_frames=0,bit_index=0;
 wire bck,ws,din;reg [31:0] serial=0;reg signed [15:0] el,er;
 piano28_core #(.ENABLE_TOUCH(1),.ENABLE_MEDIA(1),.AMP_STARTUP_CYCLES(10)) muted(.sys_clk(clk),.rst_n(rst_n),.adc_miso(4'd0),.enc_a(1'b1),.enc_b(1'b1),.dark_button_n(1'b1),.touch_keys(28'd1),.volume_percent(7'd0),.transpose_set_valid(1'b0),.transpose_set(4'd0),.playback_exclusive(exclusive),.playback_l(16'sd12345),.playback_r(-16'sd23456),.record_valid(rv0),.record_pcm(rec0),.fault(fault0));
 piano28_core #(.ENABLE_TOUCH(1),.ENABLE_MEDIA(1),.AMP_STARTUP_CYCLES(10)) loud(.sys_clk(clk),.rst_n(rst_n),.adc_miso(4'd0),.enc_a(1'b1),.enc_b(1'b1),.dark_button_n(1'b1),.touch_keys(28'd1),.volume_percent(7'd100),.transpose_set_valid(1'b0),.transpose_set(4'd0),.playback_exclusive(exclusive),.playback_l(16'sd12345),.playback_r(-16'sd23456),.record_valid(rv1),.record_pcm(rec1),.fault(fault1),.dac_bck(bck),.dac_ws(ws),.dac_din(din));
 always @(posedge clk)if(rst_n)begin #1;if(fault0||fault1)$fatal(1,"audio deadline/ADC fault");if(rv0!==rv1)$fatal(1,"record sample alignment");if(rv0)begin samples++;if(rec0!==rec1)$fatal(1,"recording depends on monitoring volume");if(rec0)nonzero++;end end
 always @(negedge bck)if(loud.u_pt8211_tx.bit_index==0)begin el=loud.audio_sample;er=loud.audio_sample_r;end
 always @(posedge bck)if(loud.reset_n)begin serial={serial[30:0],din};if(bit_index==31)begin if(serial!=={er,el})$fatal(1,"stereo file samples did not reach PT8211: right channel must precede left");serial_frames++;bit_index=0;end else bit_index++;end
 initial begin #101;rst_n=1;#8000000;exclusive=1;#100000;
  if(loud.audio_sample!=12345||loud.audio_sample_r!=-23456||muted.audio_sample||muted.audio_sample_r)$fatal(1,"playback mux/gain leaked synth or lost stereo");
  #1000000;exclusive=0;#50000;if(loud.audio_sample==12345)$fatal(1,"exit did not restore synth");
  if(samples<400||nonzero<300||serial_frames<400)$fatal(1,"coverage samples=%0d nonzero=%0d",samples,nonzero);
  $display("PASS media_audio: %0d pre-volume record samples identical at mute/unity, %0d stereo DAC frames; file exclusive, volume, synth return",samples,serial_frames);$finish;
 end
 initial begin #12000000;$fatal(1,"media audio timeout");end
endmodule
