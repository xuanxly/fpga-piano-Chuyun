`timescale 1ns/1ps
module tb_spectrum_animation;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,frame_tick=0,snapshot_valid=0;
    reg [267:0] snapshot=0;
    wire hs_out,vs_out,de_out;wire [23:0] rgb;
    spectrum_renderer dut(.clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),.snapshot_valid(snapshot_valid),
        .snapshot(snapshot),.x(10'd0),.y(10'd0),.hs(1'b1),.vs(1'b0),.de(1'b0),.hs_out(hs_out),.vs_out(vs_out),.de_out(de_out),.rgb(rgb));
    task tick;
        begin @(negedge clk); frame_tick=1; @(negedge clk);frame_tick=0; end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst_n=1;
        snapshot[7:0]=200;snapshot_valid=1;@(negedge clk);snapshot_valid=0;
        tick();if(dut.shown[7:0]!=100 || dut.peaks[7:0]!=100) $fatal(1,"spectrum attack/peak rise");
        for(integer j=0;j<10;j=j+1) tick();
        if(dut.peaks[7:0]<199) $fatal(1,"peak did not track sustained tone");
        snapshot=0;snapshot_valid=1;@(negedge clk);snapshot_valid=0;
        tick();if(dut.shown[7:0]>=200 || dut.peaks[7:0]<190) $fatal(1,"bar/peak release behavior");
        for(integer j=0;j<450;j=j+1) tick();
        if(dut.shown!=0 || dut.peaks!=0 || rgb!=0) $fatal(1,"silence must settle to zero with blanking black");
        $display("PASS spectrum_animation attack, hold, falling peak and eventual silence");$finish;
    end
    initial begin #100000;$fatal(1,"animation timeout");end
endmodule
