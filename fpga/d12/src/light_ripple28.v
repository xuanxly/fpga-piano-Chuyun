`timescale 1ns/1ps
// 28键二维灯效：四灯保持、按下边沿触发圆形波纹、多键按颜色通道取最大值。
// 距离表来自 PCB4 的112个实际灯珠坐标；音频和FFT都不参与本模块运算。
module light_ripple28 (
    input wire clk, rst_n,
    input wire frame_start, blank_frame,          // blank_frame用于启动时发送第一帧全黑
    input wire [27:0] key_gate,                   // 与音源相同的28键压力滞回结果
    input wire [6:0] read_index,
    output reg [23:0] read_grb,                   // 同步读出完整帧，busy=0后供发送器读取
    output reg busy, frame_done, overrun
);
    localparam [3:0] IDLE=0, PIXEL_INIT=1, ADDRESS=2, WAIT_ROM=3,
                     DISTANCE=4, SHAPE=5, MULTIPLY=6, COLOR=7, ACCUMULATE=8;
    reg [3:0] state;
    reg [27:0] previous_keys, pending_press, shown_keys;
    wire [27:0] new_presses = pending_press | (key_gate & ~previous_keys);
    reg [5:0] age [0:27];                         // 每键一份波纹年龄：0..31，32表示未活动
    reg [5:0] shown_age [0:27];                   // 整帧使用同一份快照，避免画面撕裂
    reg [23:0] pixels [0:111];                    // 整帧GRB缓存，发送期间不允许重绘
    reg [7:0] distances [0:3135];                 // 每灯到每键中心的四舍五入距离，单位mm
    reg [11:0] distance_addr;
    reg [7:0] distance_q;
    reg [6:0] pixel_index;
    reg [4:0] source_key;
    reg [7:0] acc_r, acc_g, acc_b;
    reg [5:0] age_q,fade_q;                       // 年龄选择、距离、轮廓、乘法分别寄存，缩短组合路径
    reg [4:0] source_q,ring_q;
    reg [8:0] delta_q;
    reg active_q;
    reg [7:0] level_q;
    reg [23:0] wave_q;
    integer i;
    initial $readmemh("rom/light_distance28.hex",distances);
    always @(posedge clk) begin
        distance_q<=distances[distance_addr];     // 显式同步ROM，允许综合成BSRAM
        if (read_index<112) read_grb<=pixels[read_index]; else read_grb<=0;
    end

    // 一个串行组有四颗灯，偶数行在PCB上从右往左串接；返回演奏位置键号。
    function [4:0] key_for_pixel;
        input [6:0] pixel;
        begin
            case (pixel[6:2])
                0:key_for_pixel=6; 1:key_for_pixel=5; 2:key_for_pixel=4; 3:key_for_pixel=3;
                4:key_for_pixel=2; 5:key_for_pixel=1; 6:key_for_pixel=0;
                7:key_for_pixel=7; 8:key_for_pixel=8; 9:key_for_pixel=9; 10:key_for_pixel=10;
                11:key_for_pixel=11; 12:key_for_pixel=12; 13:key_for_pixel=13;
                14:key_for_pixel=20; 15:key_for_pixel=19; 16:key_for_pixel=18; 17:key_for_pixel=17;
                18:key_for_pixel=16; 19:key_for_pixel=15; 20:key_for_pixel=14;
                21:key_for_pixel=21; 22:key_for_pixel=22; 23:key_for_pixel=23; 24:key_for_pixel=24;
                25:key_for_pixel=25; 26:key_for_pixel=26; 27:key_for_pixel=27;
                default:key_for_pixel=0;
            endcase
        end
    endfunction

    function [23:0] palette_rgb;
        input [4:0] key_number;
        input [7:0] level;
        begin
            // 四个音区使用青、蓝、紫、橙；单通道始终不超过32/255。
            if(key_number<7) palette_rgb={8'd0,level,(level>>1)};
            else if(key_number<14) palette_rgb={(level>>2),(level>>1),level};
            else if(key_number<21) palette_rgb={level,(level>>2),level};
            else palette_rgb={level,(level>>1),8'd0};
        end
    endfunction
    wire [4:0] owner_key = key_for_pixel(pixel_index);
    wire [23:0] held_rgb = palette_rgb(owner_key,shown_keys[owner_key] ? 8'd32 : 8'd0);
    wire [8:0] radius_mm = {1'b0,age_q[4:0],3'b000}; // 每帧向外移动8mm
    wire [8:0] delta_mm = (radius_mm > {1'b0,distance_q}) ?
                              radius_mm-{1'b0,distance_q} : {1'b0,distance_q}-radius_mm;
    wire [10:0] product = ring_q * fade_q;
    wire [7:0] next_r = acc_r>wave_q[23:16] ? acc_r : wave_q[23:16];
    wire [7:0] next_g = acc_g>wave_q[15:8] ? acc_g : wave_q[15:8];
    wire [7:0] next_b = acc_b>wave_q[7:0] ? acc_b : wave_q[7:0];

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;busy<=0;frame_done<=0;overrun<=0;previous_keys<=0;pending_press<=0;shown_keys<=0;
            distance_addr<=0;pixel_index<=0;source_key<=0;acc_r<=0;acc_g<=0;acc_b<=0;
            age_q<=32;fade_q<=0;source_q<=0;ring_q<=0;delta_q<=0;active_q<=0;level_q<=0;wave_q<=0;
            for(i=0;i<28;i=i+1) begin age[i]<=32;shown_age[i]<=32;end
        end else begin
            frame_done<=0; previous_keys<=key_gate; pending_press<=new_presses;
            if(frame_start && busy) overrun<=1;    // 供仿真和内部观察，不新增GPIO
            case(state)
                IDLE: if(frame_start) begin
                    busy<=1;pixel_index<=0;shown_keys<=blank_frame ? 28'd0 : key_gate;
                    if(blank_frame) begin
                        for(i=0;i<28;i=i+1) shown_age[i]<=32;
                    end else begin
                        pending_press<=0;         // 本帧也包括同一拍出现的新按下边沿
                        for(i=0;i<28;i=i+1) begin
                            shown_age[i]<=new_presses[i] ? 6'd0 : age[i];
                            if(new_presses[i]) age[i]<=1;
                            else if(age[i]<32) age[i]<=age[i]+1'b1;
                        end
                    end
                    state<=PIXEL_INIT;
                end
                PIXEL_INIT: begin
                    acc_r<=held_rgb[23:16];acc_g<=held_rgb[15:8];acc_b<=held_rgb[7:0];
                    source_key<=0;state<=ADDRESS;
                end
                ADDRESS: begin
                    distance_addr<=pixel_index*12'd28+source_key;state<=WAIT_ROM;
                end
                WAIT_ROM: begin
                    age_q<=shown_age[source_key];source_q<=source_key;state<=DISTANCE;
                end
                DISTANCE: begin
                    delta_q<=delta_mm;fade_q<=6'd32-age_q;active_q<=age_q<32;state<=SHAPE;
                end
                SHAPE: begin
                    ring_q<=delta_q<16 ? 5'd16-delta_q[4:0] : 5'd0;state<=MULTIPLY;
                end
                MULTIPLY: begin
                    level_q<=active_q ? {1'b0,product[10:4]} : 8'd0;state<=COLOR;
                end
                COLOR: begin wave_q<=palette_rgb(source_q,level_q);state<=ACCUMULATE;end
                ACCUMULATE: begin
                    acc_r<=next_r;acc_g<=next_g;acc_b<=next_b;
                    if(source_key==27) begin
                        pixels[pixel_index]<={next_g,next_r,next_b}; // 发出顺序为GRB
                        if(pixel_index==111) begin busy<=0;frame_done<=1;state<=IDLE;end
                        else begin pixel_index<=pixel_index+1'b1;state<=PIXEL_INIT;end
                    end else begin source_key<=source_key+1'b1;state<=ADDRESS;end
                end
                default: begin state<=IDLE;busy<=0;end
            endcase
        end
    end
endmodule
