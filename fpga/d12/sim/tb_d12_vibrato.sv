`timescale 1ns/1ps
module tb_d12_vibrato;
 reg clk=0;always #10 clk=~clk;reg rst_n=0,sample_tick=0,vibrato_enable=0;
 reg [27:0] key_gate=0;reg [335:0] key_pressure={28{12'd3072}};reg signed [3:0] transpose=0;reg [2:0] timbre_select=0;
 wire signed [15:0] mixed_sample;wire frame_done,busy,ready,deadline_fault;wire [27:0] voice_active;
 piano28_timbre_engine #(.ENABLE_VIBRATO(1)) d(.*);
 integer checks=0,frames=0,fd,slots,i,p,n;reg signed [41:0] expected;
 reg [31:0] old_phase;reg [14:0] old_age;reg signed [8:0] lfo;
 always @(negedge clk)if(rst_n&&d.busy&&d.slot==2)begin
    expected=0;
    if(vibrato_enable&&!d.note_start)begin
      if(d.profile==3&&d.age_q>=2400)expected=($signed({1'b0,d.step})*$signed(d.frame_lfo))>>>((d.age_q>=4800)?17:(d.age_q>=3600)?18:19);
      if(d.profile==4&&d.age_q>=9600)expected=($signed({1'b0,d.step})*$signed(d.frame_lfo))>>>((d.age_q>=24000)?14:(d.age_q>=16800)?15:16);
    end
    if(d.step_delta!==expected)$fatal(1,"Per-voice vibrato wrong voice%0d age%0d delta%0d expected%0d",d.voice_index,d.age_q,d.step_delta,expected);
    if(d.voice_index==0&&fd) $fwrite(fd,"%0d %0d %0d %0d %0d\n",d.profile,d.age_q,d.frame_lfo,d.step,expected);
    checks++;
 end
 task frame;
 begin
   @(negedge clk);sample_tick=1;@(negedge clk);sample_tick=0;n=0;
   while(!frame_done)begin @(negedge clk);n++;if(n>900)$fatal(1,"Audio overrun");end
   if(n!=896||deadline_fault)$fatal(1,"896-cycle schedule changed n%0d",n);
   frames++;if(fd)$fwrite(fd,"PCM %0d\n",mixed_sample);
   repeat(145)@(negedge clk);
 end endtask
 initial begin
   fd=0;repeat(5)@(negedge clk);rst_n=1;wait(ready);
   for(p=3;p<=4;p++)begin
     key_gate=0;timbre_select=p;repeat(270)frame();
     fd=$fopen($sformatf("d12_vibrato_%0d.txt",p),"w");vibrato_enable=1;key_gate=28'hfffffff;
     for(i=0;i<36000;i++)begin
       if(i==18000)key_gate[27]=0; // 独立声部释放/重触发，不能共用起音年龄。
       if(i==19000)key_gate[27]=1;
       frame();
     end
     vibrato_enable=0;repeat(2400)frame();
     key_gate=0;repeat(1200)frame();$fclose(fd);fd=0;
   end
   $display("PASS D12 vibrato %0d per-voice delta checks,%0d frames,delays/depth/ramp/retrigger/effectoff,896 cycles",checks,frames);$finish;
 end
 initial begin #3000000000;$fatal(1,"Vibrato timeout");end
endmodule
