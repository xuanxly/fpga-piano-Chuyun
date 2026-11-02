`timescale 1ns/1ps
module tb_pt8211_tx;
    reg clk=0, rst_n=0;
    always #10 clk=~clk;
    reg signed [15:0] l=16'h1357,r=16'h8ace;
    wire tick,bck,ws,din;
    pt8211_tx dut(clk,rst_n,l,r,tick,bck,ws,din);
    integer bits=0,frames=0,checks=0,cycles=0,last_tick=0,last_edge=0;
    reg tick_prev=0;
    reg [31:0] expected=0,received=0;
    reg [15:0] next_l=0,next_r=0;
    reg previous_ws=0,previous_din=0,previous_bck=0;
    integer half_period;
    task check;
        input condition;
        input [8*100-1:0] label;
        begin
            checks=checks+1;
            if (!condition) begin
                $display("FAIL %0s time=%0t frames=%0d bits=%0d got=%h want=%h",label,$time,frames,bits,received,expected);
                $fatal(1);
            end
        end
    endtask
    always @(posedge clk) begin
        #1;
        if (!rst_n) begin
            cycles=0;last_tick=0;last_edge=0;
            bits=0;tick_prev=0;previous_bck=0;
            received=0;previous_ws=0;previous_din=0;
        end else begin
            cycles=cycles+1;
            check(!(tick && tick_prev),"tick must be a single clk cycle");
            tick_prev=tick;
            if (tick) begin
                if(last_tick!=0)
                    check((cycles-last_tick==1041)||(cycles-last_tick==1042),"frame length at 50MHz");
                last_tick=cycles;
                check(bits==0,"frame capture is at frame boundary");
                expected={r,l};
                // Update BOTH source samples during transmission to detect torn frames.
                next_l=l+16'h2311;next_r=r-16'h1743;
            end
            if(bck!=previous_bck) begin
                if(last_edge!=0) begin
                    half_period=cycles-last_edge;
                    check((half_period==16)||(half_period==17),"BCK half-period bound");
                end
                last_edge=cycles;
            end
            if((!previous_bck)&&bck) begin
                check(ws==(bits>=16),"WS low is right; high is left");
                check(din===expected[31-bits],"MSB-first data including signed patterns");
                check(ws===previous_ws && din===previous_din,"data and WS stable on sampling edge");
                received={received[30:0],din};
                bits=bits+1;
                if(bits==32) begin
                    check(received===expected,"atomic stereo frame reconstruction");
                    frames=frames+1;bits=0;
                end
            end
            previous_ws=ws;previous_din=din;previous_bck=bck;
        end
    end
    always @(negedge clk) begin
        if(rst_n && bits==5) begin l<=next_l;r<=next_r;end
    end
    initial begin
        repeat(4) @(negedge clk);
        check(bck===0 && ws===0 && din===0 && tick===0,"reset outputs");
        rst_n=1;
        wait(frames==100);
        @(negedge clk);rst_n=0;
        #1;check(bck===0 && ws===0 && din===0 && tick===0,"async reset outputs");
        repeat(4) @(negedge clk);rst_n=1;
        wait(frames==103);
        $display("PASS frames=%0d checks=%0d",frames,checks);
        $finish;
    end
    initial begin #4000000;$fatal(1,"timeout");end
endmodule
