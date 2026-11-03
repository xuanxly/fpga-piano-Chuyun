`timescale 1ns/1ps
module tb_d13_audio_chain;
 reg clk=0,rst_n=0;always #10 clk=~clk;
 reg validation_page=0,validation_run=0,playback_exclusive=0;reg [5:0] validation_count=32;
 reg [2:0] fx_enabled=0;reg [20:0] fx_levels={7'd60,7'd60,7'd60};reg [27:0] touch_keys=0;
 wire i2s_bclk,i2s_lrclk,i2s_data,dac_bck,dac_ws,dac_din,pa_en,record_valid;
 wire signed [15:0] record_pcm;wire [191:0] verify_status;wire [2:0] fault;
 piano28_core #(.ENABLE_TOUCH(1),.ENABLE_MEDIA(1),.ENABLE_TIMBRE(1),.ENABLE_EFFECTS(1),.ENABLE_NEW_APPS(1),.AMP_STARTUP_CYCLES(10)) d(
  .sys_clk(clk),.rst_n(rst_n),.adc_miso(4'd0),.enc_a(1'b1),.enc_b(1'b1),.dark_button_n(1'b1),.touch_keys(touch_keys),
  .volume_percent(7'd100),.timbre_select(3'd2),.transpose_set_valid(1'b0),.transpose_set(4'd0),
  .validation_page(validation_page),.validation_run(validation_run),.validation_count(validation_count),.fx_enabled(fx_enabled),.fx_levels(fx_levels),
  .playback_exclusive(playback_exclusive),.playback_l(16'sd12345),.playback_r(-16'sd23456),
  .i2s_bclk(i2s_bclk),.i2s_lrclk(i2s_lrclk),.i2s_data(i2s_data),.verify_status(verify_status),
  .dac_bck(dac_bck),.dac_ws(dac_ws),.dac_din(dac_din),.pa_en(pa_en),.record_valid(record_valid),.record_pcm(record_pcm),.fault(fault));
 integer records=0,different=0,frames=0,words=0,read_frame=0,bits=0,pcm_nonzero=0;
 reg [31:0] left_words[0:15000],right_words[0:15000];reg [31:0] serial=0;reg old_ws=0,channel=0,collect=0;
 always @(negedge clk)if(d.reset_n)begin
  if(fault||d.fx_fault||d.test_fault)$fatal(1,"D13 audio deadline fault");
  if(record_valid)begin
   records++;if(record_pcm!==d.effected)$fatal(1,"recording is not post-FX");
   if(fx_enabled==7&&record_pcm!=d.filtered_sample)different++;
  end
  if(d.sample_tick)begin left_words[frames]={d.audio_sample,16'd0};right_words[frames]={d.audio_sample_r,16'd0};frames++;if(d.audio_sample!=0)pcm_nonzero++;end
 end
 always @(posedge i2s_bclk)if(d.reset_n)begin
  if(collect)begin
   serial={serial[30:0],i2s_data};bits++;
   if(bits==32)begin
    if(serial!==(channel?right_words[read_frame]:left_words[read_frame]))$fatal(1,"live I2S mismatch frame%0d channel%0d",read_frame,channel);
    words++;if(channel)read_frame++;
   end
  end
  if(i2s_lrclk!=old_ws)begin collect=1;channel=i2s_lrclk;bits=0;serial=0;old_ws=i2s_lrclk;end
 end
 initial begin #101;rst_n=1;wait(records>=400);touch_keys=1;fx_enabled=7;wait(records>=8000);
  $display("D13 chain coverage postFX=%0d nonzeroPCM=%0d frames=%0d different=%0d",records,pcm_nonzero,frames,different);
  if(different<4000||pcm_nonzero<7000)$fatal(1,"effect audible coverage different=%0d PCM=%0d",different,pcm_nonzero);
  playback_exclusive=1;#100000;if(d.audio_sample!=12345||d.audio_sample_r!=-23456)$fatal(1,"file must bypass effects and synth");
  playback_exclusive=0;validation_page=1;validation_run=1;#6000000;
  if(verify_status[5:0]!=32||d.test_units!=32||d.voice_active!=0)$fatal(1,"test page did not isolate32 tones from piano");
  validation_page=0;validation_run=0;#200000;
  if(d.test_units!=0||d.voice_active!=1||pa_en)$fatal(1,"exit test did not restore live organ");
  if(words<16000)$fatal(1,"serial coverage");
  $display("PASS D13 actual audio chain: %0d postFX record samples,%0d exact I2S words,allFX audible,file stereo bypass,32test isolation/exit",records,words);$finish;
 end
 initial begin #200000000;$fatal(1,"D13 audio chain timeout");end
endmodule
