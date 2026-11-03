`timescale 1ns/1ps
module tb_d12_effect_controls;
    reg clk=0;always #5 clk=~clk;reg rst=0,button=1;reg [2:0] tone=0;
    wire signed [3:0] transpose;wire dark,led,vib;wire [9:0] leds;wire [4:0] states;
    instrument_controls #(.ENABLE_TIMBRE_EFFECT(1),.BUTTON_CYCLES(2),.ENCODER_CYCLES(2),.LONG_PRESS_CYCLES(40))
        d(.clk(clk),.rst_n(rst),.enc_a(1'b1),.enc_b(1'b1),.dark_button_n(button),.transpose(transpose),.dark_mode(dark),
        .transpose_led(leds),.dark_led(led),.transpose_set_valid(1'b0),.transpose_set(4'd0),.timbre_select(tone),.vibrato_enable(vib),.effect_state(states));
    task clocks(input integer n);repeat(n)@(negedge clk);endtask
    task short_press;begin button=0;clocks(15);button=1;clocks(10);end endtask
    initial begin
        clocks(4);rst=1;clocks(10);short_press();if(!dark||!led||vib)$fatal(1,"Piano brightness failed");
        tone=3;clocks(5);if(dark||vib||led)$fatal(1,"Guitar defaults incorrect");
        short_press();if(dark||!vib||!led)$fatal(1,"Guitar vibrato toggle failed");
        tone=4;clocks(5);short_press();if(!vib||dark)$fatal(1,"Strings vibrato failed");
        button=0;clocks(80);button=1;clocks(10);if(!vib||states!=5'b11001)$fatal(1,"Long press also toggled short effect");
        tone=1;clocks(5);short_press();if(!dark||vib)$fatal(1,"EP brightness failed");
        tone=0;clocks(5);if(!dark)$fatal(1,"Per-timbre memory lost");
        tone=3;clocks(5);short_press();if(vib||dark||led)$fatal(1,"Guitar off failed");
        $display("PASS D12 independent timbre memories, release short press, long suppression");$finish;
    end
endmodule
