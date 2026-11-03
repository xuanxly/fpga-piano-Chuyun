`timescale 1ns/1ps
module tb_voice_engine_tone;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,tick=0,start=0,gate=0;
    reg [31:0] step=23409859;reg [11:0] pressure=4095;
    wire signed [15:0] voice_sample;wire voice_active;
    piano_voice voice(clk,rst_n,tick,start,gate,step,pressure,voice_sample,voice_active);
    reg [6:0] keys=0;reg [83:0] pressures={7{12'd4095}};reg signed [3:0] transpose=0;
    reg dark=0;wire signed [15:0] engine_sample;wire [3:0] active;
    piano_engine engine(clk,rst_n,tick,keys,pressures,transpose,dark,engine_sample,active);
    reg signed [15:0] tone_input=0;wire signed [15:0] tone_output;
    tone_filter tone(clk,rst_n,tick,dark,tone_input,tone_output);
    reg [2:0] freq_key=0;wire [31:0] freq_step;
    note_frequency freq(freq_key,transpose,freq_step);
    integer checks=0,i,k,t,midi,fd;
    reg [31:0] saved_phase;
    real full_energy,light_energy,normal_low,dark_low,normal_high,dark_high,total,ideal;
    function real real_abs(input real value);
        real_abs = value < 0.0 ? -value : value; // XSim 不支持 $abs，显式计算实数绝对值
    endfunction
    task check(input bit ok,input string reason);
        if(!ok) $fatal(1,"%s",reason);checks=checks+1;
    endtask
    task sample;
        @(negedge clk);tick=1;@(negedge clk);tick=0;repeat(15) @(negedge clk); // 单元测试加速节拍，仍按 48 kHz 样本解释
    endtask
    task tone_energy(input integer period,input bit darkness,output real energy);
        dark=darkness;energy=0.0;
        for(integer n=0;n<1500;n=n+1) begin
            tone_input=$rtoi(12000.0*$sin(6.283185307179586*n/period));sample();
            if(n>=500) energy=energy+$itor(tone_output)*$itor(tone_output);
        end
    endtask
    initial begin
        fd=$fopen("piano_preview_pcm.txt","w");
        repeat(3) @(negedge clk);rst_n=1;
        for(k=0;k<7;k=k+1) for(t=-5;t<=5;t=t+1) begin
            freq_key=k;transpose=t;#1;
            case(k) 0:midi=60;1:midi=62;2:midi=64;3:midi=65;4:midi=67;5:midi=69;6:midi=71;endcase
            ideal=440.0*$pow(2.0,(midi+t-69)/12.0)*4294967296.0/48000.0;
            check(real_abs($itor(freq_step)-ideal)<0.51,"all seven pitches and eleven transpose values");
        end
        @(negedge clk);transpose=0;gate=1;start=1;keys=7'b0001111; // 起音必须覆盖一个完整上升沿
        @(negedge clk);start=0;
        for(i=0;i<12000;i=i+1) begin sample();$fdisplay(fd,"%0d",engine_sample);end
        check(voice_active && voice.state==3'd3 && active==15,"attack decay sustain and four active voices");
        full_energy=0;
        for(i=0;i<1500;i=i+1) begin sample();full_energy+= $itor(voice_sample)*$itor(voice_sample);end
        pressure=1024;
        for(i=0;i<512;i=i+1) sample();
        light_energy=0;
        for(i=0;i<1500;i=i+1) begin sample();light_energy+= $itor(voice_sample)*$itor(voice_sample);end
        check(full_energy>0 && light_energy/full_energy>0.055 && light_energy/full_energy<0.075,"continuous pressure gain only multiplied once");
        saved_phase=voice.u_osc.phase_acc;step=39370534;sample();
        check(voice.u_osc.phase_acc==saved_phase+32'd39370534,"pitch change preserves phase");
        pressures[11:0]=512;
        for(i=0;i<512;i=i+1) sample();
        check(engine.g_voice[1].u_voice.pressure_gain==4095 && engine.g_voice[0].u_voice.pressure_gain<=520,"one key pressure cannot change other voice gains");
        gate=0;pressure=0;keys=7'b0001110;
        total=0;
        for(i=0;i<200;i=i+1) begin sample();total+= $itor(voice_sample)*$itor(voice_sample);$fdisplay(fd,"%0d",engine_sample);end
        check(total>0 && voice_active,"zero pressure on release preserves tail");
        for(i=0;i<4500;i=i+1) sample();
        check(!voice_active && voice_sample==0 && active==14,"release ends in exact silence independently");
        keys=7'b0101110;sample();sample();
        check(engine.u_allocator.voice_key[2:0]==5 && active==15,"engine reuses released voice for new key");
        transpose=1;sample();check(engine.g_voice[0].step>23409859,"held chord transpose updates");
        keys=0;
        for(i=0;i<4500;i=i+1) begin sample();$fdisplay(fd,"%0d",engine_sample);end
        $fclose(fd);check(active==0 && engine_sample==0,"all voices release to silence");
        tone_input=-12000;dark=1;for(i=0;i<200;i=i+1) sample();
        check(tone_output>=-12002 && tone_output<=-11998,"signed lowpass negative DC convergence");
        tone_input=12000;for(i=0;i<200;i=i+1) sample();
        check(tone_output>=11998 && tone_output<=12002,"signed lowpass positive DC convergence");
        tone_energy(48,0,normal_low);tone_energy(48,1,dark_low);
        tone_energy(6,0,normal_high);tone_energy(6,1,dark_high);
        $display("INFO tone ratios low=%f high=%f",dark_low/normal_low,dark_high/normal_high);
        check(dark_high/normal_high<0.025,"dark mode attenuates high harmonics");
        check(dark_low/normal_low>dark_high/normal_high*10.0,"dark mode changes spectral balance, not only volume");
        $display("PASS voice_engine_tone checks=%0d pressure_ratio=%f low_ratio=%f high_ratio=%f",checks,light_energy/full_energy,dark_low/normal_low,dark_high/normal_high);$finish;
    end
endmodule
