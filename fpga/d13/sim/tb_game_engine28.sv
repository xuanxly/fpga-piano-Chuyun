`timescale 1ns/1ps
module tb_game_engine28;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,page=1,write=0;reg [27:0] keys=0;reg [5:0] adr=0;reg [31:0] data=0;
    wire [31:0] read_data;wire [159:0] status;wire guide;wire [27:0] target,good,bad;
    game_engine28 #(.CLK_HZ(10000),.COUNTDOWN_MS(3)) d(clk,rst,page,keys,write,adr,data,read_data,status,guide,target,good,bad);
    task wr(input [5:0] a,input [31:0] v);begin @(negedge clk);adr=a;data=v;write=1;@(negedge clk);write=0;end endtask
    task enqueue(input [31:0] at,input [27:0] mask,input [15:0] duration,input bit last);begin wr(4,at);wr(8,{last,3'd0,mask});wr(12,duration);wr(16,1);end endtask
    task milliseconds(input integer n);begin repeat(n*10)@(negedge clk);end endtask
    task set_keys(input [27:0] v);begin @(negedge clk);keys=v;milliseconds(2);end endtask
    integer before_time,checks=0;
    initial begin
        repeat(4)@(negedge clk);rst=1;wr(0,12);
        enqueue(500,28'h11,600,0);enqueue(1200,28'h2,80,0);enqueue(1281,0,0,1);wr(0,9);
        if(target||good||bad)$fatal(1,"Countdown exposed a playable target");checks++;
        milliseconds(40);set_keys(28'h11);milliseconds(10);
        if(d.hits!=0)$fatal(1,"Held-before-window key incorrectly auto-hit");checks++;
        milliseconds(500);if(d.now_ms!=500||d.hits!=0)$fatal(1,"Practice did not wait");checks++;
        set_keys(0);set_keys(1);if(d.hits!=0)$fatal(1,"Partial chord counted");checks++;
        set_keys(28'h11);if(d.hits!=1||d.hold_mask!=28'h11||good!=28'h11)$fatal(1,"Chord/hold/feedback failed");checks++;
        milliseconds(30);if(d.score!=100||status[55:32]!=24'h000100)$fatal(1,"Score/BCD mismatch");checks++;
        set_keys(0);if(d.misses!=2)$fatal(1,"Early hold release not penalized once");checks++;
        milliseconds(800);set_keys(2);set_keys(0);milliseconds(100);
        if(!d.complete||d.hits!=2)$fatal(1,"EOF did not wait for last note end");checks++;
        wr(0,4);enqueue(250,1,80,0);enqueue(600,2,80,0);enqueue(681,0,0,1);wr(0,1);
        milliseconds(200);set_keys(1);set_keys(0);if(d.hits!=1)$fatal(1,"Challenge early window failed");checks++;
        wr(0,3);before_time=d.now_ms;milliseconds(50);if(d.now_ms!=before_time)$fatal(1,"Paused clock moved");checks++;
        wr(0,1);milliseconds(700);if(!d.complete||d.misses!=1||d.hits!=1)$fatal(1,"Challenge timeout/EOF failed");checks++;
        wr(0,4);enqueue(250,1,500,0);enqueue(900,0,0,1);wr(0,1);
        milliseconds(60);if(target)$fatal(1,"Target lit before judgment window");checks++;
        milliseconds(90);if(target!=1||!d.in_window)$fatal(1,"Lit target was not playable");checks++;
        set_keys(1);if(d.hits!=1||d.hold_end[0]<d.now_ms+497||d.hold_end[0]>d.now_ms+500)$fatal(1,"Early hit long duration not based on actual onset");checks++;
        milliseconds(500);set_keys(0);if(d.misses)$fatal(1,"Natural long-note release penalized");checks++;
        // 截止前60ms恰好允许释放，前61ms仍计漏音；覆盖双截止寄存器的边界。
        for(integer early=0;early<2;early++)begin
            wr(0,4);enqueue(100,1,500,0);enqueue(900,0,0,1);wr(0,1);
            milliseconds(200);set_keys(1);
            if(d.hold_early_end[0]+60!=d.hold_end[0])$fatal(1,"Hold cutoff arithmetic mismatch");
            wait(d.now_ms==d.hold_end[0]-60-early);set_keys(0);
            if(d.misses!=early)$fatal(1,"Hold release grace boundary early=%0d misses=%0d",early,d.misses);checks++;
        end
        wr(0,4);enqueue(100,1,500,0);enqueue(600,1,500,0);enqueue(1101,0,0,1);wr(0,1);
        milliseconds(200);set_keys(1);milliseconds(210);if(good!=1)$fatal(1,"Sustained key not marked green");checks++;
        milliseconds(50);set_keys(0);set_keys(1);if(d.hits!=2||d.misses)$fatal(1,"Repeated-key window penalized legitimate rearticulation");checks++;
        set_keys(0);wr(0,12);enqueue(10,1,80,0);wr(0,9);milliseconds(12);set_keys(1);milliseconds(20);
        before_time=d.now_ms;milliseconds(60);if(d.now_ms!=before_time||!d.waiting)$fatal(1,"Underflow advanced game time");checks++;
        page=0;milliseconds(2);if(guide||target||d.running)$fatal(1,"Page exit left guidance running");checks++;
        page=1;wr(0,12);for(integer i=0;i<33;i++)enqueue(1000+i*100,1,50,0);
        // One current event plus32 queue entries fit; the next must set fault and preserve data.
        enqueue(5000,1,50,0);if(!d.fault||d.count!=32)$fatal(1,"Queue overflow not bounded");checks++;
        $display("PASS game engine %0d scenarios: chords holds practice challenge pause EOF BCD underflow queue exit",checks);$finish;
    end
    initial begin #1000000;$fatal(1,"Game test timeout");end
endmodule

