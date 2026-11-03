`timescale 1ns/1ps
// 单独以厂商prim_sim.v编译、不定义PIANO_XSIM，检验综合实际采用的IOBUF分支。
module tb_usb_pad_vendor;
    tri pad;reg tx=0,drive=0,external_drive=0,external_data=0;wire rx;
    assign pad=external_drive?external_data:1'bz;
    usb_pad_buffer dut(pad,tx,drive,rx);
    integer k;reg expected,expected_rx;
    initial begin
        for(k=0;k<16;k++) begin
            {drive,tx,external_drive,external_data}=k;#10;
            if(!drive && !external_drive) expected=1'bz;
            else if(drive && external_drive && tx!=external_data) expected=1'bx;
            else expected=drive?tx:external_data;
            expected_rx=(expected===1'bz)?1'bx:expected; // 厂商buf门把悬空输入变为X；实板已有15k下拉。
            if(pad!==expected || rx!==expected_rx) $fatal(1,"Vendor IOBUF receive/drive mismatch combination=%b pad=%b rx=%b expected=%b/%b",k[3:0],pad,rx,expected,expected_rx);
        end
        drive=0;external_drive=1;external_data=1;tx=0;#10;
        if(pad!==1 || rx!==1) $fatal(1,"Passive receiver must read physical high despite internal TX=0");
        $display("PASS usb_pad_vendor: exact installed Gowin IOBUF model, 16 receive/drive/contention/float combinations and independent physical readback");$finish;
    end
endmodule
