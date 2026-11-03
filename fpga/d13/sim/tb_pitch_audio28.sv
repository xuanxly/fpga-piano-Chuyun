`timescale 1ns/1ps
// 独立音符数学参考核对28声部的真实DDS步进，同时检查实体键、触摸键和实际串行DAC。
module tb_pitch_audio28;
    reg sys_clk=0;always #10 sys_clk=~sys_clk;
    reg rst_n=0,connected=1,valid=0;reg [4:0] active=0;
    reg [39:0] ids=0;reg [49:0] xs=0,ys=0;
    wire cs,sck,mosi;wire [3:0] miso;wire [27:0] keys;wire [9:0] leds;
    wire [1:0] page;wire [6:0] volume;wire pv,bck,ws,din,pa;
    wire signed [15:0] pcm;wire [2:0] fault;
    piano28_touch_system #(.BOOT_CYCLES(10)) dut(.sys_clk(sys_clk),.rst_n(rst_n),.enc_a(1'b1),.enc_b(1'b1),.dark_button_n(1'b1),
        .adc_miso(miso),.touch_connected(connected),.touch_frame_valid(valid),.touch_active(active),.touch_ids(ids),.touch_xs(xs),.touch_ys(ys),
        .adc_cs_n(cs),.adc_sck(sck),.adc_mosi(mosi),.transpose_led(leds),.pa_en(pa),.ui_page(page),.ui_volume(volume),
        .monitor_keys(keys),.monitor_valid(pv),.monitor_pcm(pcm),.audio_fault(fault),.dac_bck(bck),.dac_ws(ws),.dac_din(din),.usb_diag(72'd0));
    reg [79:0] values[0:3];wire integer transactions[0:3];
    genvar b;generate for(b=0;b<4;b++) begin:adc
        mcp3008_model m(cs,sck,mosi,values[b],miso[b],transactions[b]);
    end endgenerate
    integer expected_trans=0,step_checks=0,dac_frames=0,nonzero_pcm=0,bit_index=0,i,t,yy,previous_checks;
    reg [31:0] word=0;reg signed [15:0] emitted;
    function [31:0] expected_step(input integer key_index,trans);
        integer white_note,midi;real freq;
        begin
            case(key_index%7) 0:white_note=0;1:white_note=2;2:white_note=4;3:white_note=5;4:white_note=7;5:white_note=9;default:white_note=11;endcase
            midi=48+(key_index/7)*12+white_note+trans;
            freq=440.0*(2.0**((midi-69)/12.0));
            expected_step=$rtoi(freq*4294967296.0/48000.0+0.5);
        end
    endfunction
    task send;begin @(negedge sys_clk);valid=1;@(negedge sys_clk);valid=0;repeat(3) @(negedge sys_clk);end endtask
    task finger(input integer s,id,px,py);begin active[s]=1;ids[s*8+:8]=id;xs[s*10+:10]=px;ys[s*10+:10]=py;end endtask
    always @(negedge bck) if(dut.u_piano.u_pt8211_tx.bit_index==0) emitted=dut.u_piano.audio_sample;
    always @(posedge bck) if(dut.sys_reset_n) begin
        word={word[30:0],din};
        if(ws!==(bit_index>=16)) $fatal(1,"pitch DAC channel");
        if(bit_index==31) begin
            if(word!=={emitted,emitted}) $fatal(1,"pitch path PCM did not reach stereo DAC");
            dac_frames++;bit_index=0;
        end else bit_index++;
    end
    always @(posedge sys_clk) if(dut.sys_reset_n) begin
        #1;
        if(fault || dut.fft_overrun || dut.u_lights.render_overrun) $fatal(1,"pitch integration fault");
        if(pv && pcm!=0) nonzero_pcm++;
        if(dut.u_piano.legacy_engine.u_engine.busy && dut.u_piano.legacy_engine.u_engine.slot==1 &&
           $signed(dut.u_piano.legacy_engine.u_engine.trans)==expected_trans) begin
            if(dut.u_piano.legacy_engine.u_engine.step!==expected_step(dut.u_piano.legacy_engine.u_engine.voice_index,expected_trans))
                $fatal(1,"DDS step key=%0d transpose=%0d got=%0d expected=%0d",dut.u_piano.legacy_engine.u_engine.voice_index,expected_trans,
                    dut.u_piano.legacy_engine.u_engine.step,expected_step(dut.u_piano.legacy_engine.u_engine.voice_index,expected_trans));
            step_checks++;
        end
    end
    initial begin
        for(i=0;i<4;i++) values[i]=0;
        #201;rst_n=1;#2000000;values[3][69:60]=700;
        finger(0,10,20,310);send();#21000000;
        if(keys!==28'h8000001 || nonzero_pcm<500 || pa) $fatal(1,"physical and touch audio startup");
        // 持续按住C3和实体B6，逐档移动音调柱；所有28声部的查表地址同步移调。
        for(t=-5;t<=5;t++) begin
            case(t) -5:yy=400;-4:yy=366;-3:yy=333;-2:yy=299;-1:yy=266;0:yy=232;
                1:yy=198;2:yy=165;3:yy=131;4:yy=98;default:yy=64;endcase
            previous_checks=step_checks;expected_trans=t;finger(1,11,776,yy);send();#1000000;
            if($signed(dut.transpose)!=t || step_checks-previous_checks<28 || keys!==28'h8000001)
                $fatal(1,"held-key transpose not applied t=%0d",t);
        end
        // 沿用D7帧边界邮箱：最坏需要两帧才显示最新快照，等待35ms覆盖这一边界。
        #35000000;
        if($signed(dut.legacy_video.u_renderer.transpose)!=5 || leds!=10'b1111100000)
            $fatal(1,"display/LEDs not synchronized: renderer=%0d core=%0d leds=%b",$signed(dut.legacy_video.u_renderer.transpose),$signed(dut.transpose),leds);
        active=0;send();finger(0,20,740,450);send();active=0;send();
        if(page!=0 || keys!==28'h8000000) $fatal(1,"Home stopped physical key");
        expected_trans=-5;finger(0,21,776,400);send();active=0;send();#1000000;
        if($signed(dut.transpose)!=-5 || leds!=10'b0000011111 || volume!=25 || keys!==28'h8000000)
            $fatal(1,"Home pitch control did not reach physical note");
        connected=0;#100000;if($signed(dut.transpose)!=-5 || keys!==28'h8000000) $fatal(1,"USB detach altered physical pitch");
        if(dac_frames<2000 || nonzero_pcm<1000) $fatal(1,"pitch audio coverage");
        $display("PASS pitch_audio28: 11 semitones, all28 DDS steps checked=%0d, touch+physical held keys, Home, retained pitch, LCD/LEDs and %0d stereo DAC frames, nonzero PCM=%0d",step_checks,dac_frames,nonzero_pcm);$finish;
    end
    initial begin #100000000;$fatal(1,"pitch audio timeout");end
endmodule
