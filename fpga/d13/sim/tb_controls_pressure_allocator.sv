`timescale 1ns/1ps
module tb_controls_pressure_allocator;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0, enc_a=1,enc_b=1,button_n=1;
    wire signed [3:0] transpose; wire dark, dark_led; wire [9:0] leds;
    instrument_controls #(.BUTTON_CYCLES(4),.ENCODER_CYCLES(3)) controls(
        clk,rst_n,enc_a,enc_b,button_n,transpose,dark,leds,dark_led,1'b0,4'sd0);
    reg raw_valid=0;reg [2:0] raw_channel=0;reg [9:0] raw_sample=100; // MCP3008 十位输入
    wire [6:0] pgate, invalid_gate;wire [83:0] pressure, invalid_pressure;
    pressure_frontend #(.BASELINE({7{10'd100}}),.FULL_SCALE({7{10'd900}}),.PRESS_ON(400),.PRESS_OFF(200)) front(
        clk,rst_n,raw_valid,raw_channel,raw_sample,pgate,pressure);
    pressure_frontend #(.BASELINE({7{10'd100}}),.FULL_SCALE({7{10'd100}})) invalid(
        clk,rst_n,raw_valid,raw_channel,raw_sample,invalid_gate,invalid_pressure);
    reg sample_tick=0;reg [6:0] keys=0;reg [3:0] active=0;
    wire [3:0] gates,starts;wire [11:0] owners;
    voice_allocator allocator(clk,rst_n,sample_tick,keys,active,gates,starts,owners);
    integer checks=0,i;
    reg [3:0] starts_seen=0; // 收集一帧内七个处理周期的起音事件
    task check(input bit ok,input string reason);
        if(!ok) $fatal(1,"%s",reason);checks=checks+1;
    endtask
    task settle;repeat(12) @(negedge clk);endtask
    task turn(input bit forward);
        // 所选编码器每一格只有两次相位转换；相邻定位格的 AB 状态交替。
        repeat(2) begin
            case({enc_a,enc_b})
                2'b11: {enc_a,enc_b}=forward ? 2'b10 : 2'b01;
                2'b10: {enc_a,enc_b}=forward ? 2'b00 : 2'b11;
                2'b00: {enc_a,enc_b}=forward ? 2'b01 : 2'b10;
                2'b01: {enc_a,enc_b}=forward ? 2'b11 : 2'b00;
            endcase
            settle();
        end
    endtask
    task pressure_update(input integer channel,input integer val);
        @(negedge clk);raw_valid=1;raw_channel=channel;raw_sample=val;
        @(negedge clk);raw_valid=0;
    endtask
    task allocate(input [6:0] pressed);
        @(negedge clk);keys=pressed;sample_tick=1;
        @(negedge clk);sample_tick=0;starts_seen=0;
        repeat(8) begin @(negedge clk);starts_seen=starts_seen|starts; end // 等待声部分配完整批次
    endtask
    initial begin
        repeat(3) @(negedge clk);rst_n=1;settle();
        check(transpose==0 && leds==0 && !dark,"control reset");
        button_n=0;@(negedge clk);button_n=1;settle();check(!dark,"button bounce rejected");
        button_n=0;settle();check(dark && dark_led,"dark button first press");
        settle();check(dark,"button hold does not toggle again");
        button_n=1;settle();button_n=0;settle();check(!dark,"dark button second press");
        button_n=1;settle();
        turn(1);check(transpose==1 && leds==10'b0000100000,"one physical detent is one semitone");
        turn(0);check(transpose==0,"one reverse detent returns to zero");
        {enc_a,enc_b}=2'b10;settle();{enc_a,enc_b}=2'b11;settle();
        check(transpose==0,"encoder partial movement and return does not change pitch");
        {enc_a,enc_b}=2'b00;settle();{enc_a,enc_b}=2'b11;settle();
        check(transpose==0,"illegal simultaneous AB jumps do not change pitch");
        for(i=0;i<8;i=i+1) turn(1);
        check(transpose==5 && leds==10'b1111100000,"upper transpose limit and LEDs");
        for(i=0;i<5;i=i+1) turn(0);
        check(transpose==0 && leds==0,"return to original pitch");
        for(i=0;i<8;i=i+1) turn(0);
        check(transpose==-5 && leds==10'b0000011111,"lower transpose limit and LEDs");
        for(i=0;i<35;i=i+1) pressure_update(0,1023);
        check(pgate==7'b0000001 && pressure[11:0]==4095,"pressure full-scale clipping and independent gates");
        check(pressure[23:12]==0,"unrelated pressure channel unaffected");
        for(i=0;i<40;i=i+1) pressure_update(0,160);
        check(pgate[0] && pressure[11:0]<400 && pressure[11:0]>200,"pressure hysteresis holds");
        for(i=0;i<40;i=i+1) pressure_update(0,120);
        check(!pgate[0],"pressure release threshold");
        for(i=0;i<40;i=i+1) pressure_update(0,10);
        check(pressure[11:0]==0 && invalid_pressure==0 && invalid_gate==0,"baseline clamp and invalid calibration");
        allocate(7'b0001111);check(gates==4'b1111 && starts_seen==4'b1111,"four simultaneous keys");active=4'b1111;
        check(owners=={3'd3,3'd2,3'd1,3'd0},"voice ownership order");
        allocate(7'b0011111);check(starts_seen==0 && owners=={3'd3,3'd2,3'd1,3'd0},"fifth held key ignored");
        allocate(7'b0011110);check(gates==4'b1110 && starts_seen==0,"independent release; fifth key not auto-allocated");
        allocate(7'b0111110);check(owners[2:0]==5 && starts_seen==1 && gates==15,"released voice reused");
        allocate(7'b0111111);allocate(7'b0111110);
        check(gates[0] && owners[2:0]==5,"old key release cannot turn off reassigned voice");
        allocate(7'b0101110);allocate(7'b0111110);
        check(starts_seen==0,"fifth key still blocked while all voices held");
        allocate(7'b0001110);allocate(7'b0001110);active[0]=0;
        allocate(7'b1001110);check(owners[2:0]==6 && starts_seen==1,"idle voice preferred");
        $display("PASS controls_pressure_allocator checks=%0d",checks);$finish;
    end
endmodule
