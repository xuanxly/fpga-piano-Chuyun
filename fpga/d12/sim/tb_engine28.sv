`timescale 1ns/1ps
// 与独立Python逐采样数学模型逐位比较，并检查28个上下文是否互相串扰。
module engine28_case #(parameter FAST=0)(output reg finished=0);
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,tick=0;reg [27:0] gates=0;reg [335:0] pressures=0;reg signed [3:0] trans=0;
    wire signed [15:0] mixed;wire done,busy,ready,fault;wire [27:0] active;
    piano28_engine #(.ATTACK_STEP(FAST ? 4096:512),.DECAY_STEP(FAST ? 512:4),.RELEASE_STEP(FAST ? 1024:16)) dut(
        clk,rst_n,tick,gates,pressures,trans,mixed,done,active,busy,ready,fault);
    reg [367:0] stim[0:799];reg [43:0] expected[0:799];reg [63:0] contexts[0:22399];
    integer f,k,cycles,peak=0;
    initial begin
        $readmemh("engine28_stim.hex",stim);
        if(FAST) begin $readmemh("engine28_expected_1.hex",expected);$readmemh("engine28_context_1.hex",contexts);end
        else begin $readmemh("engine28_expected_0.hex",expected);$readmemh("engine28_context_0.hex",contexts);end
        #201;rst_n=1;wait(ready);
        for(f=0;f<800;f=f+1) begin
            @(negedge clk);{gates,pressures,trans}=stim[f];tick=1;
            @(posedge clk);#1;
            @(negedge clk);tick=0;
            // 帧中修改输入，证明所有声音使用帧开始时的同一份状态快照。
            gates=~gates;pressures=~pressures;trans=0;
            cycles=0;
            while(!done && cycles<1000) begin @(posedge clk);#1;cycles=cycles+1;end
            if(cycles!=896 || busy || fault) $fatal(1,"28 engine deadline fast=%0d frame=%0d cycles=%0d",FAST,f,cycles);
            if({active,mixed}!==expected[f]) $fatal(1,"28 engine PCM fast=%0d frame=%0d got=%h expected=%h",FAST,f,{active,mixed},expected[f]);
            for(k=0;k<28;k=k+1) if(dut.context_mem[k]!==contexts[f*28+k])
                $fatal(1,"28 context fast=%0d frame=%0d key=%0d got=%h exp=%h",FAST,f,k,dut.context_mem[k],contexts[f*28+k]);
            if($signed(mixed)>16384 || $signed(mixed)<-16384) $fatal(1,"output limiter overflow");
            if($signed(mixed)>peak) peak=$signed(mixed);
            repeat(103) @(posedge clk); // 每1000周期启动一次，较真实48kHz节拍更紧
        end
        // 主动制造超时，确认错误锁存；复位必须清除所有28键上下文。
        @(negedge clk);tick=1;@(negedge clk);tick=0;repeat(5) @(negedge clk);tick=1;
        @(negedge clk);tick=0;if(!fault) $fatal(1,"deadline error was not latched");
        rst_n=0;repeat(4) @(negedge clk);rst_n=1;wait(ready);#1;
        if(fault || active || mixed) $fatal(1,"reset did not clear output and fault");
        for(k=0;k<28;k=k+1) if(dut.context_mem[k]!==0) $fatal(1,"context reset key=%0d",k);
        $display("PASS engine28 fast=%0d: 800 PCM frames, 22400 exact contexts, 896 cycles/frame, peak=%0d; deadline/reset checked",FAST,peak);
        finished=1;
    end
endmodule
module tb_engine28;
    wire a,b;engine28_case #(.FAST(0)) normal(a);engine28_case #(.FAST(1)) fast(b);
    initial begin wait(a && b);$display("PASS engine28 both independent reference cases");$finish;end
    initial begin #17000000;$fatal(1,"engine28 timeout");end
endmodule
