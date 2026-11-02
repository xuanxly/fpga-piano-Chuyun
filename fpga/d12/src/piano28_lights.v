`timescale 1ns/1ps
// 单时钟域灯光外设：先完成一帧计算，再发送该帧，避免同一帧边发边改。
module piano28_lights #(
    parameter integer ENABLE_GAME=0, FRAME_CYCLES=833333         // 50MHz下约60Hz；测试可缩短，但必须容纳完整发送
)(
    input wire clk,rst_n,
    input wire [27:0] key_gate,input wire guide_active,input wire [27:0] guide_keys,good_keys,bad_keys,
    output wire led_data
);
    localparam [1:0] WAIT_FRAME=0, RENDER=1, TRANSMIT=2;
    reg [1:0] state;
    reg [31:0] frame_counter;
    reg frame_due,boot_blank,render_blank,render_start,tx_start;
    wire render_busy,render_done,render_overrun,tx_ready,tx_busy,tx_done;
    wire [6:0] read_index;
    wire [23:0] pixel_grb;
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

    reg game_frame;reg [27:0] shown_guide,shown_good,shown_bad;
    wire [4:0] owner=key_for_pixel(read_index);
    wire [23:0] guide_grb=shown_bad[owner]?24'h002000:shown_good[owner]?24'h200000:shown_guide[owner]?24'h080020:24'd0;
    reg [23:0] guide_q;
    always @(posedge clk)guide_q<=guide_grb;
    light_ripple28 u_render(.clk(clk),.rst_n(rst_n),.frame_start(render_start),.blank_frame(render_blank),
        .key_gate(key_gate),.read_index(read_index),.read_grb(pixel_grb),
        .busy(render_busy),.frame_done(render_done),.overrun(render_overrun));
    ws2812_frame_tx u_tx(.clk(clk),.rst_n(rst_n),.start(tx_start),.pixel_grb(game_frame?guide_q:pixel_grb),
        .read_index(read_index),.ready(tx_ready),.busy(tx_busy),.frame_done(tx_done),.led_data(led_data));
    // synthesis translate_off
    initial if(FRAME_CYCLES<225000) $fatal(1,"Lighting period shorter than render plus complete WS2812 frame");
    // synthesis translate_on
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=WAIT_FRAME;frame_counter<=0;frame_due<=1;boot_blank<=1;
            render_blank<=1;render_start<=0;tx_start<=0;game_frame<=0;shown_guide<=0;shown_good<=0;shown_bad<=0;
        end else begin
            render_start<=0;tx_start<=0;
            if(frame_counter==FRAME_CYCLES-1) begin frame_counter<=0;frame_due<=1;end
            else frame_counter<=frame_counter+1'b1;
            case(state)
                WAIT_FRAME: if(frame_due && tx_ready) begin
                    render_start<=1;render_blank<=boot_blank;boot_blank<=0;
                    game_frame<=ENABLE_GAME&&guide_active&&!boot_blank;shown_guide<=guide_keys;shown_good<=good_keys;shown_bad<=bad_keys;
                    frame_due<=0;state<=RENDER;
                end
                RENDER: if(render_done) begin tx_start<=1;state<=TRANSMIT;end
                TRANSMIT: if(tx_done) state<=WAIT_FRAME;
                default: state<=WAIT_FRAME;
            endcase
        end
    end
endmodule
