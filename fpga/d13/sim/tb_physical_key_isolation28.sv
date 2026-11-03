`timescale 1ns/1ps
// 实体键隔离回归：真实SPI时序模型 -> 压力前端 -> 发声核心 -> 新旧屏幕键格。
// 模型输入相互独立；本测试不能代替PCB模拟电压、焊接和机械串扰的检查。
module tb_physical_key_isolation28;
    reg clk=0; always #10 clk=~clk;
    reg rst_n=0;
    wire cs,sck,mosi; wire [3:0] miso;
    wire [27:0] keys; wire pcm_valid; wire signed [15:0] pcm; wire [2:0] fault;
    piano28_core #(.ENABLE_TOUCH(1)) core(
        .sys_clk(clk),.rst_n(rst_n),.adc_miso(miso),.enc_a(1'b1),.enc_b(1'b1),.dark_button_n(1'b1),
        .adc_cs_n(cs),.adc_sck(sck),.adc_mosi(mosi),.monitor_keys(keys),
        .monitor_valid(pcm_valid),.monitor_pcm(pcm),.fault(fault),.touch_keys(28'd0),.volume_percent(7'd100));
    reg [79:0] values[0:3]; wire integer transactions[0:3];
    genvar b; generate for(b=0;b<4;b=b+1) begin:model
        mcp3008_model adc(cs,sck,mosi,values[b],miso[b],transactions[b]);
    end endgenerate

    reg snapshot_valid=0; reg [298:0] snapshot=0;
    reg [9:0] x=0,y=0;
    wire [23:0] rgb,old_rgb;
    piano_ui_renderer video(.clk(clk),.rst_n(rst_n),.frame_tick(1'b0),
        .snapshot_valid(snapshot_valid),.snapshot(snapshot),.x(x),.y(y),.hs(1'b1),.vs(1'b0),.de(1'b1),.rgb(rgb));
    spectrum_renderer #(.KEY_COUNT(28)) old_video(.clk(clk),.rst_n(rst_n),.frame_tick(1'b0),
        .snapshot_valid(snapshot_valid),.snapshot(snapshot[288:0]),.x(x),.y(y),.hs(1'b1),.vs(1'b0),.de(1'b1),.rgb(old_rgb));
    reg [27:0] allowed=0;
    integer raw_count=0,pcm_nonzero=0,frames=0,checked_pixels=0;
    integer key_id,bank,channel,pg,j; reg [23:0] expected; reg [27:0] wanted;
    // 从SPI读数开始检查，防止只检查屏幕而漏掉音频中的多余音符。
    always @(posedge clk) begin
        #1;
        if(rst_n && core.reset_n) begin
            if(fault!==0) $fatal(1,"core fault=%b",fault);
            if((keys & ~allowed)!==0) $fatal(1,"extra physical gate allowed=%h actual=%h",allowed,keys);
            if((core.voice_active & ~allowed)!==0) $fatal(1,"extra audio voice allowed=%h actual=%h",allowed,core.voice_active);
            if(core.raw_valid) begin
                if(core.raw_sample!==values[core.raw_key/7][(core.raw_key%7)*10+:10])
                    $fatal(1,"ADC sample routed to wrong key key=%0d sample=%0d",core.raw_key,core.raw_sample);
                raw_count++;
            end
            if(pcm_valid && pcm!=0) pcm_nonzero++;
            if(core.engine_done) frames++;
        end
    end
    task reset_case;
        begin
            @(negedge clk);rst_n=0;allowed=0;snapshot_valid=0;pcm_nonzero=0;
            for(integer n=0;n<4;n++) values[n]=0;
            repeat(8) @(negedge clk);
        end
    endtask
    task snapshot_page(input integer page_id);
        begin
            @(negedge clk);snapshot=0;snapshot[283:256]=keys;
            snapshot[290:289]=page_id;snapshot[297:291]=25;snapshot_valid=1;
            @(negedge clk);snapshot_valid=0;
        end
    endtask
    task check_cells(input [27:0] expected_keys);
        begin
            for(integer page_id=1;page_id<=2;page_id++) begin
                snapshot_page(page_id);
                for(integer n=0;n<28;n++) begin
                    case(n/7)
                        0:expected=24'h32d3b8;1:expected=24'h4794ed;
                        2:expected=24'hb978ef;default:expected=24'heab15b;
                    endcase
                    if(!expected_keys[n]) expected=24'hd9e2ef;
                    @(negedge clk);x=18+(n%7)*96;y=(page_id==1 ? 306:98)+(n/7)*(page_id==1 ? 28:80);
                    repeat(2) @(posedge clk);#1;
                    if(rgb!==expected) $fatal(1,"touch-page false highlight page=%0d cell=%0d rgb=%h expected=%h",page_id,n,rgb,expected);
                    checked_pixels++;
                end
            end
            // 旧频谱页面也验证，避免只在新界面排除错亮。
            for(integer n=0;n<28;n++) begin
                @(negedge clk);x=18+(n%7)*60;y=402+(n/7)*20;
                @(posedge clk);#1;
                if(old_rgb!==(expected_keys[n] ? 24'h32d39a:24'hd9e2ef))
                    $fatal(1,"legacy-page false highlight cell=%0d rgb=%h",n,old_rgb);
                checked_pixels++;
            end
        end
    endtask
    initial begin
        for(key_id=0;key_id<28;key_id++) begin
            reset_case();
            wanted=28'd1<<key_id;allowed=wanted;
            values[key_id/7][(key_id%7)*10+:10]=800;
            rst_n=1;
            #2500000; // 2.5ms覆盖至少两轮真实1kHz采样和多帧音频。
            if(keys!==wanted || core.voice_active!==wanted || pcm_nonzero<10)
                $fatal(1,"single-key isolation key=%0d keys=%h voices=%h nonzero=%0d",key_id,keys,core.voice_active,pcm_nonzero);
            check_cells(wanted);
            $display("CHECK single key=%0d only gate/voice, 3 pages exact; PCM=%0d",key_id,pcm_nonzero);
        end
        // 特别覆盖F3/G3交替和真实双键；不能通过屏蔽相邻键掩盖故障。
        reset_case();allowed=28'h18;values[0][3*10+:10]=800;values[0][4*10+:10]=800;rst_n=1;
        #2500000;
        if(keys!==28'h18 || core.voice_active!==28'h18) $fatal(1,"F3+G3 legitimate chord lost");
        check_cells(28'h18);
        // 放开F3后G3必须持续发声，滤波/释放尾音结束后只剩G3。
        @(negedge clk);values[0][3*10+:10]=0;
        #110000000; // 默认包络RELEASE_STEP=16，65535/16/48kHz约85ms，另留压力滤波时间。
        if(keys!==28'h10 || core.voice_active!==28'h10) $fatal(1,"F3 release leaked while G3 held keys=%h voices=%h",keys,core.voice_active);
        allowed=28'h10;check_cells(28'h10);
        @(negedge clk);values[0][4*10+:10]=0;
        #110000000; // 检查尾音结束后的状态，不能把正常释放包络误判为串键。
        if(keys!==0 || core.voice_active!==0) $fatal(1,"G3 release leaked keys=%h voices=%h",keys,core.voice_active);
        allowed=0;check_cells(0);
        $display("PASS physical_key_isolation28: all 28 individual ADC inputs, gates/audio voices, %0d key pixels across 3 pages, F3+G3 chord and independent release; samples=%0d audio_frames=%0d",checked_pixels,raw_count,frames);
        $finish;
    end
    initial begin #340000000;$fatal(1,"isolation regression timeout");end
endmodule
