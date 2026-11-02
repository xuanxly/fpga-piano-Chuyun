`timescale 1ns/1ps
module tb_spectrum_video;
    reg src_clk=0; always #10 src_clk=~src_clk;
    reg clk=0; always #16.666666667 clk=~clk;
    reg rst_n=0;
    reg [31:0] sequence_id=0;
    always @(posedge src_clk) if(rst_n) sequence_id<=sequence_id+1;
    wire [267:0] received;
    wire received_valid;
    wire [9:0] x,y; wire hs,vs,de,frame_tick;
    spectrum_timing timing(.*);
    spectrum_cdc cdc(.src_clk(src_clk),.src_rst_n(rst_n),.src_data({12'habc,{8{sequence_id}}}),
        .dst_clk(clk),.dst_rst_n(rst_n),.dst_frame(frame_tick),.dst_data(received),.dst_valid(received_valid));
    reg [267:0] snapshot=0;
    reg snapshot_valid=0;
    wire hs_out,vs_out,de_out; wire [23:0] rgb;
    spectrum_renderer renderer(.*);
    integer frame_count=0,pixels=0,active_pixels=0,hs_pixels=0,vs_pixels=0,snapshots=0;
    integer image_file;
    reg [267:0] previous_received=0;
    reg sampled_hs,sampled_vs,sampled_de;
    integer px,py;
    always @(negedge clk) if(rst_n) begin
        snapshot_valid=frame_tick;
        if(frame_tick) begin
            for(integer k=0;k<32;k=k+1) snapshot[k*8 +: 8]=50+((k*47)%190);
            snapshot[262:256]=7'b1010101; snapshot[266:263]=-3; snapshot[267]=1;
        end
    end
    always @(posedge clk) if(rst_n) begin
        px=x; py=y; sampled_hs=hs; sampled_vs=vs; sampled_de=de;
        pixels=pixels+1;
        if(de) active_pixels=active_pixels+1;
        if(!hs) hs_pixels=hs_pixels+1;
        if(vs) vs_pixels=vs_pixels+1;
        if(received_valid) begin
            if(x!=1 || y!=480) $fatal(1,"CDC changed outside vertical blank");
            if(received[267:256]!==12'habc) $fatal(1,"CDC header mismatch");
            for(integer j=0;j<8;j=j+1)
                if(received[j*32 +: 32]!==received[31:0]) $fatal(1,"CDC torn multi-bit snapshot");
            snapshots=snapshots+1;
        end else if(received!==previous_received) $fatal(1,"CDC bus changed without valid");
        previous_received=received;
        #1;
        if({hs_out,vs_out,de_out}!=={sampled_hs,sampled_vs,sampled_de}) $fatal(1,"RGB/sync pipeline misalignment");
        if(!de_out && rgb!==0) $fatal(1,"nonblack blanking");
        if(frame_count==4 && sampled_de) $fwrite(image_file,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);
        if(px==999 && py==499) begin
            if(pixels!=500000 || active_pixels!=384000 || hs_pixels!=36000 || vs_pixels!=7000)
                $fatal(1,"video geometry frame=%0d pixels=%0d active=%0d hs=%0d vs=%0d",frame_count,pixels,active_pixels,hs_pixels,vs_pixels);
            pixels=0;active_pixels=0;hs_pixels=0;vs_pixels=0;frame_count=frame_count+1;
            if(frame_count==6) begin
                $fclose(image_file);
                if(snapshots<5 || renderer.shown==0 || renderer.peaks==0) $fatal(1,"snapshot/render coverage");
                $display("PASS spectrum_video frames=%0d snapshots=%0d 800x480 active, 1000x500 total, RGB/sync aligned",frame_count,snapshots);
                $finish;
            end
        end
    end
    initial begin
        image_file=$fopen("spectrum_preview.ppm","w"); $fwrite(image_file,"P3\n800 480\n255\n");
        repeat(4) @(negedge clk); rst_n=1;
    end
    initial begin #110000000;$fatal(1,"video timeout");end
endmodule
