`timescale 1ns/1ps
module tb_pressure28;
    function [279:0] calibration(input integer full);
        integer k;begin calibration=0;for(k=0;k<28;k=k+1)
            calibration[k*10+:10]=full ? (k==27 ? 91:800+k*3) : (10+k*3);end
    endfunction
    localparam [279:0] BASE=calibration(0),FULL=calibration(1); // 最后一键故意无效标定区间
    reg clk=0;always #10 clk=~clk;reg rst_n=0,valid=0;reg [4:0] key=0;reg [9:0] sample=0;
    wire [27:0] gates;wire [335:0] pressure;wire fault,updated;wire [4:0] updated_key;
    pressure28_frontend #(.BASELINE(BASE),.FULL_SCALE(FULL)) dut(clk,rst_n,valid,key,sample,gates,pressure,fault,updated,updated_key);
    integer filtered[0:27],expected_pressure[0:27],expected_gate[0:27];
    integer received=0,sent=0,k,b,channel,round_id,delta,step,new_value,base,full,norm;
    reg checking=1;
    task send(input integer address,input integer value);
        begin
            @(negedge clk);valid=1;key=address;sample=value;
            base=BASE[address*10+:10];full=FULL[address*10+:10];delta=value-filtered[address];step=delta>>>2;
            if(delta>0 && step==0) step=1;new_value=filtered[address]+step;filtered[address]=new_value;
            if(full<=base || new_value<=base) norm=0;else if(new_value>=full) norm=4095;else norm=((new_value-base)*4095)/(full-base);
            expected_pressure[address]=norm;
            if(full<=base) expected_gate[address]=0;
            else if(!expected_gate[address] && norm>=160) expected_gate[address]=1;
            else if(expected_gate[address] && norm<=100) expected_gate[address]=0;
            sent=sent+1;
        end
    endtask
    always @(posedge clk) begin #1;if(rst_n && checking && updated) begin
        if(pressure[updated_key*12+:12]!==expected_pressure[updated_key] || gates[updated_key]!==expected_gate[updated_key][0])
            $fatal(1,"pressure key=%0d got=%0d/%0d expected=%0d/%0d",updated_key,pressure[updated_key*12+:12],gates[updated_key],expected_pressure[updated_key],expected_gate[updated_key]);
        received=received+1;
    end end
    initial begin
        for(k=0;k<28;k=k+1) begin filtered[k]=BASE[k*10+:10];expected_pressure[k]=0;expected_gate[k]=0;end
        #201;rst_n=1;
        for(round_id=0;round_id<56;round_id=round_id+1) for(channel=0;channel<7;channel=channel+1) begin
            for(b=0;b<4;b=b+1) send(b*7+channel,round_id<20 ? 1023 : round_id<36 ? 0 : ((b*233+channel*71+round_id*29)%1024));
            @(negedge clk);valid=0;repeat(150) @(negedge clk); // 四样本连续到达，快于真实硬件的7142周期间隔
        end
        repeat(160) @(negedge clk);
        if(fault || received!=sent) $fatal(1,"pressure queue loss received=%0d sent=%0d fault=%b",received,sent,fault);
        if(gates[27] || pressure[335:324]) $fatal(1,"invalid calibration must mute that key");
        checking=0;key=31;valid=1;@(negedge clk);valid=0;#1;if(!fault) $fatal(1,"invalid key was not detected");
        rst_n=0;repeat(3) @(negedge clk);rst_n=1;
        repeat(20) begin @(negedge clk);valid=1;key=3;sample=900;end
        @(negedge clk);valid=0;#1;if(!fault) $fatal(1,"FIFO overflow was not detected");
        $display("PASS pressure28: %0d samples, all calibration/filter/hysteresis values exact; invalid-key, invalid-span, overflow checked",received);$finish;
    end
endmodule
