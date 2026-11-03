`timescale 1ns/1ps
// 从真实引脚边沿解码，不使用发送器内部状态判断位值。
module tb_ws2812_frame_tx;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,start=0;reg [23:0] pixel=0;
    wire [6:0] index;wire ready,busy,done,data;
    reg [23:0] seed=24'habcdef;
    ws2812_frame_tx dut(clk,rst_n,start,pixel,index,ready,busy,done,data);
    function [23:0] pattern(input integer n);
        begin
            if(n==0) pattern=0;else if(n==1) pattern=24'hffffff;
            else if(n==2) pattern=24'h55aa81;else pattern=(n*24'h012345)^seed;
        end
    endfunction
    always @(posedge clk) pixel<=pattern(index);   // 模拟同步读存储器
    integer frames=0,zeros=0,ones=0;
    task receive_frame;
        integer n,b;time rise_at,fall_at,high_ns,low_ns;reg [23:0] word;
        begin
            @(posedge data);
            for(n=0;n<112;n=n+1) begin
                word=0;
                for(b=23;b>=0;b=b-1) begin
                    rise_at=$time;@(negedge data);fall_at=$time;high_ns=fall_at-rise_at;
                    if(high_ns!=320 && high_ns!=640) $fatal(1,"WS2812 high pulse %0t",high_ns);
                    word={word[22:0],high_ns==640};
                    if(high_ns==640) ones=ones+1;else zeros=zeros+1;
                    if(n!=111 || b!=0) begin
                        @(posedge data);low_ns=$time-fall_at;
                        if(low_ns!=1260-high_ns+(b==0 ? 40:0)) $fatal(1,"WS2812 low pulse %0t",low_ns);
                    end
                end
                if(word!==pattern(n)) $fatal(1,"WS2812 D%03d decoded=%h expected=%h",n+1,word,pattern(n));
            end
            wait(done);
            if($time-fall_at<320000 || data!==0 || !ready) $fatal(1,"WS2812 reset/latch gap");
            frames=frames+1;
        end
    endtask
    task send_and_check;
        begin
            wait(ready);@(negedge clk);start=1;@(negedge clk);start=0;
            fork
                receive_frame();
                begin #50000;@(negedge clk);start=1;@(negedge clk);start=0;end // 忙时启动不得打断本帧
            join
        end
    endtask
    initial begin
        #101;rst_n=1;#319000;if(data!==0 || ready) $fatal(1,"WS2812 startup reset too short");
        send_and_check();seed=24'h765432;send_and_check();
        // 发送中异步复位，输出立即变低；重新启动后必须恢复完整112灯帧。
        wait(ready);@(negedge clk);start=1;@(negedge clk);start=0;
        #50000;rst_n=0;#1;if(data!==0) $fatal(1,"WS2812 reset output");
        #100;rst_n=1;seed=24'hc3d2e1;send_and_check();
        if(frames!=3 || zeros==0 || ones==0) $fatal(1,"WS2812 insufficient coverage");
        $display("PASS ws2812_frame_tx: 3 exact 112-pixel GRB frames, 0/1 timing and 320us latch, busy start ignored, midframe reset recovery");$finish;
    end
    initial begin #15000000;$fatal(1,"WS2812 timeout");end
endmodule
