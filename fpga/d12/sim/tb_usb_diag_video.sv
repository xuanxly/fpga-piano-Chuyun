`timescale 1ns/1ps
module tb_usb_diag_video;
    reg clk=0;always #5 clk=~clk;reg rst_n=0;
    reg [71:0] diag=0;reg [298:0] snapshot=0;reg snapshot_valid=0;
    reg [9:0] x=0,y=0;wire [23:0] rgb;
    piano_ui_renderer #(.ENABLE_USB_DIAG(1)) dut(.clk(clk),.rst_n(rst_n),.frame_tick(1'b0),
        .snapshot_valid(snapshot_valid),.snapshot(snapshot),.x(x),.y(y),.hs(1'b1),.vs(1'b0),.de(1'b1),.rgb(rgb),.usb_diag(diag));
    reg [8*52-1:0] first="USB D9 C1 L1 R1 B0 J1 T1 X0 S0B P3 H0 A1 D10 O0 U210";
    reg [8*31-1:0] second="ERR2 AT0B P3 TR3 LEN00 RX00 N01";
    integer i,pg,xx,yy,f,checked=0;reg [7:0] c;reg [34:0] font;
    task pixel(input integer px,py,input [23:0] expected);
        begin @(negedge clk);x=px;y=py;repeat(2) @(posedge clk);#1;
            if(rgb!==expected) $fatal(1,"USB diagnostic pixel (%0d,%0d) got=%h expected=%h",px,py,rgb,expected);
            checked++;
        end
    endtask
    initial begin
        diag[66:64]=7;diag[61:60]=3;diag[59:52]=1;diag[35:32]=3;
        diag[31:28]=2;diag[27:24]=3;diag[23:16]=11;diag[13:12]=2;diag[11:8]=3;diag[7:0]=11;
        diag[68]=1;diag[69]=1;
        #21;rst_n=1;
        for(pg=0;pg<3;pg++) begin
            @(negedge clk);snapshot[290:289]=pg;snapshot_valid=1;
            @(negedge clk);snapshot_valid=0;
            for(i=0;i<52;i++) begin
                c=first[(51-i)*8+:8];
                if(dut.diag_char(0,i,diag)!==c) $fatal(1,"Top diagnostic field %0d",i);
                font=dut.glyph(c);pixel(16+i*12,32,font[34]?24'he6edf5:24'h09111d);
            end
            for(i=0;i<31;i++) begin
                c=second[(30-i)*8+:8];
                if(dut.diag_char(1,i,diag)!==c) $fatal(1,"Bottom diagnostic field %0d",i);
                font=dut.glyph(c);pixel(16+i*12,466,font[34]?24'he6edf5:24'h09111d);
            end
        end
        // 保存真实RTL输出供交付前目视核对，当前停在大键盘页面。
        f=$fopen("usb_diag_preview.ppm","w");$fwrite(f,"P3\n800 480\n255\n");
        for(yy=0;yy<480;yy++) for(xx=0;xx<800;xx++) begin
            @(negedge clk);x=xx;y=yy;repeat(2) @(posedge clk);#1;
            $fwrite(f,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);
        end
        $fclose(f);
        $display("PASS usb_diag_video: all state/error hex fields and %0d pixels across 3 pages, two-cycle RGB, RTL screenshot",checked);$finish;
    end
endmodule
