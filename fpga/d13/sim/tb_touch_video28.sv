`timescale 1ns/1ps
module tb_touch_video28;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,frame_tick=0,snapshot_valid=0;reg [298:0] snapshot=0;
    reg [9:0] x=0,y=0;reg hs=1,vs=0,de=1;
    wire hs_out,vs_out,de_out;wire [23:0] rgb;
    wire [71:0] usb_diag=72'd0; // 该回归关闭诊断行；显式接入后增端口，避免旧.*缺少同名信号。
    piano_ui_renderer dut(.*);
    // 对照D7第一轮原渲染器：覆盖三页全部1152000像素及连续时序，拒绝颜色/延迟变化。
    wire [23:0] reference_rgb;wire reference_hs,reference_vs,reference_de;
    piano_ui_renderer_reference reference(.clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),
        .snapshot_valid(snapshot_valid),.snapshot(snapshot),.x(x),.y(y),.hs(hs),.vs(vs),.de(de),
        .rgb(reference_rgb),.hs_out(reference_hs),.vs_out(reference_vs),.de_out(reference_de),.usb_diag(usb_diag));
    reg compare_left_d=0,compare_left_q=0;
    always @(posedge clk) begin
        compare_left_d<=x<704;compare_left_q<=compare_left_d;
    end
    always @(posedge clk) if(rst_n) begin
        #1;
        if({hs_out,vs_out,de_out}!=={reference_hs,reference_vs,reference_de} ||
           (compare_left_q && rgb!==reference_rgb))
            $fatal(1,"D8 changed preserved left region or sync x=%0d y=%0d",x,y);
    end
    integer file_handle,xx,yy,pp,i,t,tone_position,checked=0;reg [23:0] wanted,previous_color;
    reg previous_hs,previous_vs,previous_de;
    task pixel(input integer px,py,input [23:0] expected);begin
        @(negedge clk);x=px;y=py;repeat(2) @(posedge clk);#1;
        if(rgb!==expected || !de_out || hs_out!==hs || vs_out!==vs)
            $fatal(1,"pixel (%d,%d) got=%h expected=%h",px,py,rgb,expected);
        checked++;
    end endtask
    task snap(input integer pg);begin
        @(negedge clk);snapshot[290:289]=pg;snapshot_valid=1;
        @(negedge clk);snapshot_valid=0;
    end endtask
    initial begin
        snapshot[298]=1;snapshot[297:291]=25;snapshot[283:256]=28'ha5c39e1;
        snapshot[287:284]=-3;
        for(i=0;i<32;i++) snapshot[i*8+:8]=60+(i*47)%190;
        #21;rst_n=1;snap(1);
        for(i=0;i<20;i++) begin @(negedge clk);frame_tick=1;@(negedge clk);frame_tick=0;end
        for(pp=0;pp<3;pp++) begin
            snap(pp);
            pixel(740,100,24'h263d54);pixel(740,380,24'h32d39a);pixel(710,438,24'h265faa);
            pixel(776,300,24'heab15b);pixel(776,333,24'hffffff);pixel(776,232,24'h8295ad);
            pixel(750,300,24'h142339); // 两柱之间留空，防止界面误连成一条。
            if(pp==0) begin pixel(90,160,24'h153c53);pixel(390,160,24'h223655);pixel(18,306,24'h09111d);end
            else for(i=0;i<28;i++) begin
                case(i/7) 0:wanted=24'h32d3b8;1:wanted=24'h4794ed;2:wanted=24'hb978ef;3:wanted=24'heab15b;endcase
                if(!snapshot[256+i]) wanted=24'hd9e2ef;
                pixel(18+(i%7)*96,((pp==1)?306:98)+(i/7)*((pp==1)?28:80),wanted);
            end
            case(pp) 0:file_handle=$fopen("touch_home.ppm","w");1:file_handle=$fopen("touch_spectrum.ppm","w");2:file_handle=$fopen("touch_keyboard.ppm","w");endcase
            $fwrite(file_handle,"P3\n800 480\n255\n");
            for(yy=0;yy<480;yy++) for(xx=0;xx<800;xx++) begin
                @(negedge clk);x=xx;y=yy;repeat(2) @(posedge clk);#1;
                if(hs_out!==hs || vs_out!==vs || !de_out) $fatal(1,"sync pipeline");
                $fwrite(file_handle,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);
            end
            $fclose(file_handle);
        end
        // 音调柄的位置用独立整数公式核对全部11档，中心线在0档变为白色柄。
        for(t=-5;t<=5;t++) begin
            @(negedge clk);snapshot[287:284]=t;snapshot_valid=1;
            @(negedge clk);snapshot_valid=0;
            tone_position=64+((5-t)*336+5)/10;
            pixel(776,tone_position,24'hffffff);
            pixel(776,232,t==0 ? 24'hffffff : 24'h8295ad);
        end
        // 连续每拍一个不同像素，验证新增两级流水不会漏像素或错开HS/VS/DE。
        for(i=0;i<200;i++) begin
            @(negedge clk);de=(i%4)!=0;hs=i%2;vs=(i%3)==0;
            case(i%3)
                0:begin x=740;y=100;wanted=24'h263d54;end
                1:begin x=740;y=380;wanted=24'h32d39a;end
                2:begin x=710;y=438;wanted=24'h265faa;end
            endcase
            if(!de) wanted=0;
            @(posedge clk);#1;
            if(i!=0 && (rgb!==previous_color || hs_out!==previous_hs || vs_out!==previous_vs || de_out!==previous_de)) $fatal(1,"streamed two-cycle pixel/sync mismatch");
            previous_color=wanted;previous_hs=hs;previous_vs=vs;previous_de=de;
        end
        @(posedge clk);#1;
        if(rgb!==previous_color || hs_out!==previous_hs || vs_out!==previous_vs || de_out!==previous_de) $fatal(1,"last streamed pixel");
        @(negedge clk);de=0;repeat(2) @(posedge clk);#1;if(rgb!=0 || de_out) $fatal(1,"blanking");
        $display("PASS touch_video28: 1013760 preserved-left pixels equal D7 reference, 3 full RTL screenshots, %0d targeted pixels, 200 continuous pixels and unchanged two-cycle sync",checked);$finish;
    end
endmodule
