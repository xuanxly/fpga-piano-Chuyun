`timescale 1ns/1ps
module tb_touch_ui28;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,frame_valid=0,connected=1;reg [4:0] active=0;
    reg [39:0] ids=0;reg [49:0] xs=0,ys=0;
    wire [27:0] touch_keys;wire [6:0] volume_percent;wire [1:0] page;
    wire transpose_set_valid;wire signed [3:0] transpose_set;
    touch_ui28 dut(.*);
    task send;begin @(negedge clk);frame_valid=1;@(negedge clk);frame_valid=0;#1;end endtask
    task clear;begin active=0;send();end endtask
    task finger(input integer s,id,x,y);begin active[s]=1;ids[s*8+:8]=id;xs[s*10+:10]=x;ys[s*10+:10]=y;end endtask
    task tap(input integer x,y);begin clear();finger(0,1,x,y);send();clear();end endtask
    integer k,r,c,checks=0,gx,gy,gpage,expected;
    reg [27:0] physical_keys;reg [335:0] physical_pressure;
    wire [27:0] keys;wire [335:0] pressure;
    touch_merge28 merge(.*);
    initial begin
        // 对优化后的矩形解码穷举两页所有像素，与原来的除法定义比较。
        for(gpage=1;gpage<=2;gpage++) for(gy=0;gy<480;gy++) for(gx=0;gx<800;gx++) begin
            expected=31;
            if(gx>=16 && gx<688 && (gx-16)%96<90) begin
                if(gpage==1 && gy>=304 && gy<416 && (gy-304)%28<24) expected=((gy-304)/28)*7+(gx-16)/96;
                if(gpage==2 && gy>=96 && gy<416 && (gy-96)%80<74) expected=((gy-96)/80)*7+(gx-16)/96;
            end
            if(dut.key_at(gpage,gx,gy)!==expected[4:0]) $fatal(1,"key geometry x=%d y=%d page=%d",gx,gy,gpage);
        end
        for(gy=0;gy<1024;gy++) begin
            expected=gy<=64?100:(gy>=400?0:((400-gy)*100+168)/336);
            if(dut.volume_at(gy)!==expected[6:0]) $fatal(1,"volume mapping y=%d",gy);
        end
        physical_keys=0;physical_pressure=0;#31;rst_n=1;#41;
        if(page!=1 || volume_percent!=25) $fatal(1,"startup UI");
        for(k=0;k<28;k=k+1) begin
            clear();r=k/7;c=k%7;finger(0,k,18+c*96,306+r*28);send();
            if(touch_keys!==(28'd1<<k)) $fatal(1,"small keyboard key %d",k);checks++;
        end
        clear();finger(0,10,20,310);finger(1,11,20,310);send();
        if(touch_keys!=1) $fatal(1,"two fingers one key");
        active[0]=0;send();if(touch_keys!=1) $fatal(1,"premature release");
        // 同一个ID换槽位，仍保持原来的琴键归属。
        active=0;finger(4,11,116,310);send();if(touch_keys!=2) $fatal(1,"ID reorder/slide");
        xs[49:40]=700;send();if(touch_keys!=0) $fatal(1,"slide out release");
        clear();finger(0,42,728,64);finger(1,43,20,310);finger(2,44,116,310);send();
        if(volume_percent!=100 || touch_keys!=3) $fatal(1,"volume plus chord");
        // 音量手指拖进键盘区域仍只改变音量，不触发琴键。
        xs[9:0]=20;ys[9:0]=400;send();
        if(volume_percent!=0 || touch_keys!=3) $fatal(1,"volume capture");
        active=0;finger(4,42,15,64);finger(1,43,20,310);finger(2,44,116,310);send();
        if(volume_percent!=100 || touch_keys!=3) $fatal(1,"volume ID reorder");
        // 页面切换，压力音继续，当前手指禁止穿透新页面。
        physical_keys=28'd1;physical_pressure[11:0]=3000;
        finger(3,50,740,450);send();
        if(page!=0 || touch_keys!=0 || keys!=1 || pressure[11:0]!=3000) $fatal(1,"Home stopped physical note");
        active[3]=0;send();xs[19:10]=100;ys[19:10]=200;send();
        if(page!=0) $fatal(1,"old finger navigated through");
        clear();tap(500,200);if(page!=2) $fatal(1,"keyboard app");
        for(k=0;k<28;k=k+1) begin
            clear();finger(0,k,18+(k%7)*96,98+(k/7)*80);send();
            if(touch_keys!==(28'd1<<k)) $fatal(1,"large keyboard %d",k);checks++;
        end
        clear();finger(0,1,20,100);send();if(pressure[11:0]!=3000) $fatal(1,"max source gain");
        clear();if(keys!=1) $fatal(1,"touch release lost FSR");
        physical_keys=0;finger(0,2,20,100);send();if(pressure[11:0]!=2600) $fatal(1,"touch velocity");
        connected=0;#41;if(touch_keys!=0) $fatal(1,"disconnect stuck note");
        connected=1;tap(740,450);tap(100,200);if(page!=1) $fatal(1,"spectrum app");
        // Home上也可调音量，NAK/没有新帧时持续按住不松手。
        tap(740,450);finger(0,1,728,232);send();if(volume_percent!=50) $fatal(1,"Home volume");
        tap(100,200);finger(0,2,20,310);send();repeat(1000) @(posedge clk);
        if(touch_keys!=1) $fatal(1,"no report released held note");
        $display("PASS touch_ui28: %0d keys + 768000 geometry points + 1024 volume coordinates, multi-contact ownership, reorder, slide, Home, two apps, volume and physical merge",checks);$finish;
    end
endmodule
