`timescale 1ns/1ps
// 逐帧对照独立Python参考；校验每个灯的颜色、蛇形地址、多键和短触发行为。
module tb_light_ripple28;
    localparam integer FRAMES=230;                // 由参考脚本生成，读取时另核对文件结束标记
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,frame_start=0,blank_frame=0;
    reg [27:0] keys=0;
    reg [6:0] rd=0;
    wire [23:0] grb;
    wire busy,done,overrun;
    light_ripple28 dut(clk,rst_n,frame_start,blank_frame,keys,rd,grb,busy,done,overrun);
    reg [56:0] stim[0:FRAMES-1];
    reg [23:0] expected[0:FRAMES*112-1];
    integer f,p,checked=0;
    initial begin
        $readmemh("light_stim.hex",stim);$readmemh("light_expected.hex",expected);
        #101;rst_n=1;
        for(f=0;f<FRAMES;f=f+1) begin
            if(^stim[f]===1'bx) $fatal(1,"Missing lighting stimulus frame %0d",f);
            @(negedge clk);keys=stim[f][27:0]|stim[f][55:28];blank_frame=stim[f][56];
            repeat(2) @(negedge clk);
            keys=stim[f][27:0];repeat(2) @(negedge clk);
            frame_start=1;@(negedge clk);frame_start=0;
            wait(done);@(negedge clk);
            for(p=0;p<112;p=p+1) begin
                rd=p;repeat(2) @(negedge clk);
                if(grb!==expected[f*112+p]) $fatal(1,"Light mismatch frame=%0d D%03d got=%h expected=%h",f,p+1,grb,expected[f*112+p]);
                checked=checked+1;
            end
        end
        if(overrun) $fatal(1,"Renderer unexpectedly overrun");
        // 忙时重复启动必须报告错误，不能破坏已经计算的快照。
        @(negedge clk);frame_start=1;@(negedge clk);frame_start=0;
        repeat(5) @(negedge clk);frame_start=1;@(negedge clk);frame_start=0;
        wait(done);if(!overrun) $fatal(1,"Renderer overrun not reported");
        @(negedge clk);rst_n=0;@(negedge clk);rst_n=1;
        if(overrun) $fatal(1,"Renderer reset did not clear fault");
        $display("PASS light_ripple28: %0d frames, %0d exact GRB pixels; 28 individual keys, all-held, release, retrigger, short pulse, overlap and overrun/reset",FRAMES,checked);
        $finish;
    end
    initial begin #150000000;$fatal(1,"Lighting renderer timeout");end
endmodule
