`timescale 1ns/1ps
module tb_ws170120_reports;
    reg clk=0;always #8.333333 clk=~clk;
    reg rst_n=0,connected=1,valid=0;reg [6:0] len=11;reg [87:0] data=0;
    wire frame_valid;wire [4:0] active;wire [39:0] ids;wire [49:0] xs,ys;wire error;
    ws170120_reports #(.INCOMPLETE_CYCLES(100)) dut(clk,rst_n,connected,valid,len,data,frame_valid,active,ids,xs,ys,error);
    reg [234:0] vectors[0:7301];integer i,frames=0,max_active=0,n,k;
    task send(input [87:0] d);begin @(negedge clk);data=d;valid=1;@(posedge clk);#1;end endtask
    task stop_send;begin @(negedge clk);valid=0;end endtask
    function [87:0] report(input [7:0] cnt,cid,input tip,input [15:0] x,y,stamp);
        report={cnt,stamp,y,x,8'd5,cid,7'd0,tip,8'd1};
    endfunction
    initial begin
        $readmemh("touch_capture.hex",vectors);#61;rst_n=1;
        for(i=0;i<7302;i++) begin
            send(vectors[i][87:0]);
            if(frame_valid!==vectors[i][234]) $fatal(1,"frame publication mismatch at actual report %0d",i);
            if({active,ids,xs,ys}!==vectors[i][233:88]) $fatal(1,"actual report %0d snapshot mismatch",i);
            if(frame_valid) begin
                frames++;n=0;for(k=0;k<5;k++) n+=active[k];if(n>max_active) max_active=n;
            end
            stop_send();repeat(2) @(negedge clk);
        end
        if(active!=0 || max_active!=5 || error) $fatal(1,"capture coverage/final release");
        send(report(1,20,1,800,480,16'hffff));
        if(!frame_valid || xs[9:0]!=799 || ys[9:0]!=479) $fatal(1,"inclusive edge mapping");stop_send();
        repeat(150) @(negedge clk);if(active!=1) $fatal(1,"idle/NAK incorrectly releases held touch");
        send(report(1,20,0,800,480,16'h0000));if(!frame_valid || active!=0) $fatal(1,"timestamp wrap release");stop_send();
        send(report(2,21,1,100,100,16'h0001));if(frame_valid) $fatal(1,"partial frame leaked");stop_send();
        repeat(110) @(negedge clk);if(active!=0 || !error) $fatal(1,"partial frame timeout");
        send(report(1,21,1,100,100,16'h0002));stop_send();
        send(report(1,22,1,801,100,16'h0003));if(frame_valid || ids[7:0]!=21) $fatal(1,"out of range accepted");stop_send();
        len=10;send(report(1,22,1,100,100,16'h0004));if(frame_valid) $fatal(1,"short report accepted");stop_send();len=11;
        connected=0;repeat(3) @(negedge clk);if(active!=0) $fatal(1,"disconnect stuck");
        $display("PASS ws170120_reports: 7302 actual reports, %0d complete frames, five contacts, release, duplicates, wrap, timeout, invalid length/coordinates",frames);$finish;
    end
    initial begin #3000000;$fatal(1,"reports timeout");end
endmodule
