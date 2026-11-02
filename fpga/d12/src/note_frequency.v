`timescale 1ns/1ps
// DDS 公式：phase_step = round(音符频率 * 2^32 / 48000)。
module note_frequency (
    input wire [2:0] key_index,
    input wire signed [3:0] transpose,
    output reg [31:0] phase_step
);
    reg signed [7:0] base_note, actual_note;
    always @* begin
        case (key_index)
            0: base_note = 60; 1: base_note = 62; 2: base_note = 64;
            3: base_note = 65; 4: base_note = 67; 5: base_note = 69;
            6: base_note = 71; default: base_note = 60; // 七个白键 C4 到 B4
        endcase
        actual_note = base_note + {{4{transpose[3]}}, transpose}; // 变调作用于当前及后续音符
        case (actual_note)
            8'sd55: phase_step = 32'd17537579;
            8'sd56: phase_step = 32'd18580418;
            8'sd57: phase_step = 32'd19685267;
            8'sd58: phase_step = 32'd20855814;
            8'sd59: phase_step = 32'd22095965;
            8'sd60: phase_step = 32'd23409859;
            8'sd61: phase_step = 32'd24801882;
            8'sd62: phase_step = 32'd26276679;
            8'sd63: phase_step = 32'd27839171;
            8'sd64: phase_step = 32'd29494575;
            8'sd65: phase_step = 32'd31248413;
            8'sd66: phase_step = 32'd33106541;
            8'sd67: phase_step = 32'd35075158;
            8'sd68: phase_step = 32'd37160835;
            8'sd69: phase_step = 32'd39370534;
            8'sd70: phase_step = 32'd41711627;
            8'sd71: phase_step = 32'd44191930;
            8'sd72: phase_step = 32'd46819719;
            8'sd73: phase_step = 32'd49603764;
            8'sd74: phase_step = 32'd52553357;
            8'sd75: phase_step = 32'd55678342;
            8'sd76: phase_step = 32'd58989149;
            default: phase_step = 32'd0;
        endcase
        if (key_index == 7) phase_step = 0; // 未分配声部
    end
endmodule
