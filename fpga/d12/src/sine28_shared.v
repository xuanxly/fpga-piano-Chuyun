`timescale 1ns/1ps
module sine28_shared(input wire clk,input wire [31:0] phase,output reg signed [15:0] sample_out);
    function [15:0] quarter;
        input [4:0] addr;
        begin case(addr)
            0:quarter=0;1:quarter=3212;2:quarter=6393;3:quarter=9512;4:quarter=12539;5:quarter=15446;
            6:quarter=18204;7:quarter=20787;8:quarter=23170;9:quarter=25329;10:quarter=27245;11:quarter=28898;
            12:quarter=30273;13:quarter=31356;14:quarter=32137;15:quarter=32609;default:quarter=32767;
        endcase end
    endfunction
    reg [14:0] pos;reg sign0,sign1,sign2;reg [15:0] base,delta,base_delay;reg [9:0] fraction;
    reg [25:0] product;
    wire [15:0] magnitude=base_delay+product[25:10];
    always @(posedge clk) begin
        pos<=phase[30] ? 15'd16384-{1'b0,phase[29:16]} : {1'b0,phase[29:16]};sign0<=phase[31];
        base<=quarter(pos[14:10]);delta<=quarter(pos[14:10]+5'd1)-quarter(pos[14:10]);fraction<=pos[9:0];sign1<=sign0;
        product<=delta*fraction;base_delay<=base;sign2<=sign1; // 共用一个插值乘法器，三个泛音连续进入
        sample_out<=sign2 ? -$signed(magnitude) : $signed(magnitude); // 四级流水线，调度器等待有效结果
    end
endmodule
