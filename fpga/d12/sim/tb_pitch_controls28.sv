`timescale 1ns/1ps
// 触摸绝对设值与旋钮增量竞争时，只有同一个移调状态，且触摸同拍优先。
module tb_pitch_controls28;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,enc_a=1,enc_b=1,transpose_set_valid=0;
    reg signed [3:0] transpose_set=0;wire signed [3:0] transpose;
    wire [9:0] leds;wire dark,dark_led;
    instrument_controls #(.ENCODER_CYCLES(3),.ENABLE_TRANSPOSE_SET(1)) dut(
        .clk(clk),.rst_n(rst_n),.enc_a(enc_a),.enc_b(enc_b),.dark_button_n(1'b1),
        .transpose(transpose),.dark_mode(dark),.transpose_led(leds),.dark_led(dark_led),
        .transpose_set_valid(transpose_set_valid),.transpose_set(transpose_set));
    integer t,want,checks=0;
    task check(input bit ok,input string why);begin if(!ok) $fatal(1,"%s",why);checks++;end endtask
    task write_trans(input integer value);begin
        @(negedge clk);transpose_set=value;transpose_set_valid=1;
        @(negedge clk);transpose_set_valid=0;repeat(2) @(negedge clk);
    end endtask
    initial begin
        #51;rst_n=1;repeat(12) @(negedge clk);
        for(t=-8;t<8;t++) begin
            write_trans(t);want=t<-5 ? -5 : t>5 ? 5 : t;
            check($signed(transpose)==want,"signed clamping across every input code");
        end
        write_trans(0);
        @(negedge clk);enc_b=0;repeat(12) @(negedge clk); // 11->10，尚未走完一格。
        check(transpose==0 && dut.quarter_count==1,"first half-detent");
        enc_a=0;
        wait({dut.a,dut.b}==2'b00 && dut.previous_ab==2'b10);
        @(negedge clk);transpose_set=-2;transpose_set_valid=1;
        @(negedge clk);transpose_set_valid=0;
        check(transpose==-2 && dut.quarter_count==0,"touch wins exact rotary completion cycle");
        enc_b=1;repeat(12) @(negedge clk);
        check(transpose==-2 && dut.quarter_count==1,"no residual half-edge after touch write");
        enc_a=1;repeat(12) @(negedge clk);
        check(transpose==-1 && leds==10'b0000010000,"new detent increments from touch-selected value");
        $display("PASS pitch_controls28 checks=%0d: signed clamp all16 codes, exact-cycle arbitration, residual edge clear and rotary continuation",checks);$finish;
    end
    initial begin #20000;$fatal(1,"pitch controls timeout");end
endmodule
