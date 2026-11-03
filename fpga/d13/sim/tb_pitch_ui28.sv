`timescale 1ns/1ps
// 验证真实UI快照到共同移调寄存器及十颗LED，不直接修改产品内部状态。
module tb_pitch_ui28;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,frame_valid=0,connected=1,enc_a=1,enc_b=1;
    reg [4:0] active=0;reg [39:0] ids=0;reg [49:0] xs=0,ys=0;
    wire [27:0] touch_keys;wire [6:0] volume_percent;wire [1:0] page;
    wire transpose_set_valid;wire signed [3:0] transpose_set,transpose;
    wire [9:0] leds;wire dark,dark_led;
    touch_ui28 ui(.*);
    instrument_controls #(.BUTTON_CYCLES(4),.ENCODER_CYCLES(3),.ENABLE_TRANSPOSE_SET(1)) controls(
        .clk(clk),.rst_n(rst_n),.enc_a(enc_a),.enc_b(enc_b),.dark_button_n(1'b1),
        .transpose(transpose),.dark_mode(dark),.transpose_led(leds),.dark_led(dark_led),
        .transpose_set_valid(transpose_set_valid),.transpose_set(transpose_set));
    integer checks=0,commands=0,k,expected,count_before;
    reg was_valid=0;
    always @(posedge clk) if(rst_n) begin
        if(transpose_set_valid) commands++;
        if(was_valid && transpose_set_valid) $fatal(1,"transpose command was not one cycle");
        was_valid<=transpose_set_valid;
    end
    task check(input bit ok,input string why);
        begin if(!ok) $fatal(1,"%s",why);checks++;end
    endtask
    task send;
        begin @(negedge clk);frame_valid=1;@(negedge clk);frame_valid=0;repeat(2) @(negedge clk);end
    endtask
    task clear;begin active=0;send();end endtask
    task finger(input integer slot,id,px,py);
        begin active[slot]=1;ids[slot*8+:8]=id;xs[slot*10+:10]=px;ys[slot*10+:10]=py;end
    endtask
    task tap(input integer px,py);
        begin clear();finger(0,1,px,py);send();clear();end
    endtask
    function [9:0] led_expected(input integer trans);
        integer i;begin led_expected=0;for(i=1;i<=5;i++) begin
            if(trans>=i) led_expected[4+i]=1;
            if(trans<=-i) led_expected[5-i]=1;
        end end
    endfunction
    task turn(input bit forward);
        begin repeat(2) begin
            @(negedge clk);
            case({enc_a,enc_b})
                3: {enc_a,enc_b}=forward?2:1;
                2: {enc_a,enc_b}=forward?0:3;
                0: {enc_a,enc_b}=forward?1:2;
                1: {enc_a,enc_b}=forward?3:0;
            endcase
            repeat(12) @(negedge clk);
        end end
    endtask
    initial begin
        #51;rst_n=1;repeat(12) @(negedge clk);
        check(transpose==0 && leds==0 && volume_percent==25,"startup original pitch and volume");
        // 独立数学定义，穷举所有10位纵坐标；包含柱外拖动的上下钳位。
        for(k=0;k<1024;k++) begin
            expected=k<=64 ? 5 : k>=400 ? -5 : ((400-k)*10+168)/336-5;
            check($signed(ui.tone_at(k))==expected,$sformatf("tone mapping y=%0d",k));
            clear();finger(0,20,776,232);send();ys[9:0]=k;send();
            check($signed(transpose)==expected && leds==led_expected(expected),"UI command and LED mapping");
            check(touch_keys==0 && volume_percent==25,"tone must not trigger key or volume");
        end
        // 双柱的精确横向命中边界，中间4像素空隙不应改变任一柱。
        tap(776,232);tap(704,64);check(volume_percent==100 && transpose==0,"left edge volume");
        tap(749,400);check(volume_percent==0 && transpose==0,"right edge volume");
        count_before=commands;tap(750,64);tap(753,64);check(commands==count_before && volume_percent==0,"column separator");
        tap(754,64);check(transpose==5 && volume_percent==0,"left edge tone");
        tap(799,400);check(transpose==-5 && volume_percent==0,"right edge tone");
        // 五指同帧：音量、音调和三个不同琴键；两柱手指跨出区域仍不会变成琴键。
        clear();finger(0,10,728,64);finger(1,11,776,64);
        finger(2,12,20,310);finger(3,13,116,310);finger(4,14,212,310);send();
        check(volume_percent==100 && transpose==5 && touch_keys==7,"two sliders plus three-note chord");
        xs[9:0]=776;ys[9:0]=400;xs[19:10]=20;ys[19:10]=400;send();
        check(volume_percent==0 && transpose==-5 && touch_keys==7,"cross-drag capture");
        active=0;finger(4,10,20,232);finger(3,11,20,232);finger(0,12,20,310);send();
        check(volume_percent==50 && transpose==0 && touch_keys==1,"both owner IDs reorder");
        clear();finger(0,20,776,64);finger(1,21,776,400);send();
        check(transpose==5,"second tone finger cannot steal ownership");active[0]=0;send();
        check(transpose==5,"blocked second finger cannot acquire without new down");
        // 页面导航保留两柱归属，原琴键手指不穿透至另一页面。
        clear();finger(0,30,776,131);finger(1,31,728,232);finger(2,32,740,450);send();
        check(page==0 && transpose==3 && volume_percent==50 && touch_keys==0,"Home retains two controls");
        active[2]=0;xs[9:0]=20;ys[9:0]=299;send();check(transpose==-2,"tone capture survives Home");
        clear();tap(500,200);check(page==2 && transpose==-2 && volume_percent==50,"keyboard app preserves values");
        clear();finger(0,40,20,100);send();xs[9:0]=776;ys[9:0]=64;send();
        check(transpose==-2 && touch_keys==0,"key finger cannot become tone finger");
        // 无新报告/USB NAK不改变音调；断开释放触摸但保留已经选定的值。
        tap(776,131);count_before=commands;repeat(100) @(negedge clk);
        check(transpose==3 && commands==count_before,"idle keeps pitch without repeating commands");
        connected=0;repeat(3) @(negedge clk);check(transpose==3 && touch_keys==0,"disconnect keeps chosen pitch");
        connected=1;clear();turn(1);check(transpose==4 && leds==led_expected(4),"rotary continues from touch-selected pitch");
        turn(0);check(transpose==3,"rotary reverse after touch");
        tap(776,232);check(transpose==0 && leds==0,"center restores original pitch");
        rst_n=0;repeat(2) @(negedge clk);rst_n=1;repeat(3) @(negedge clk);
        check(transpose==0 && volume_percent==25,"reset defaults");
        $display("PASS pitch_ui28 checks=%0d: 1024 coordinates, 11 steps, LEDs, bounds, ownership, five fingers, Home, persistence, rotary continuation",checks);$finish;
    end
    initial begin #2000000;$fatal(1,"pitch UI timeout");end
endmodule
