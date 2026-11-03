`timescale 1ns/1ps
module tb_video28;
    reg src_clk=0; always #10 src_clk=~src_clk;
    reg clk=0; always #16.666666667 clk=~clk;
    reg rst_n=0;
    reg [31:0] sequence_id=0;
    always @(posedge src_clk) if(rst_n) sequence_id<=sequence_id+1;
    wire [288:0] received;
    wire received_valid;
    wire [9:0] x,y; wire hs,vs,de,frame_tick;
    spectrum_timing timing(.*);
    spectrum_cdc #(.WIDTH(289)) cdc(.src_clk(src_clk),.src_rst_n(rst_n),.src_data({33'h15a5c39e1,{8{sequence_id}}}),
        .dst_clk(clk),.dst_rst_n(rst_n),.dst_frame(frame_tick),.dst_data(received),.dst_valid(received_valid));
    reg [288:0] snapshot=0;
    reg snapshot_valid=0;
    wire hs_out,vs_out,de_out; wire [23:0] rgb;
    spectrum_renderer #(.KEY_COUNT(28)) renderer(.*);
    integer frame_count=0,pixels=0,active_pixels=0,hs_pixels=0,vs_pixels=0,snapshots=0;
    integer image_file; integer key_pixels=0;
    reg [288:0] previous_received=0;
    reg sampled_hs,sampled_vs,sampled_de;
    integer px,py;
    always @(negedge clk) if(rst_n) begin
        snapshot_valid=frame_tick;
        if(frame_tick) begin
            for(integer k=0;k<32;k=k+1) snapshot[k*8 +: 8]=50+((k*47)%190);
            snapshot[283:256]=28'ha5c39e1; snapshot[287:284]=-3; snapshot[288]=1;
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
            if(received[288:256]!==33'h15a5c39e1) $fatal(1,"CDC header mismatch");
            for(integer j=0;j<8;j=j+1)
                if(received[j*32 +: 32]!==received[31:0]) $fatal(1,"CDC torn multi-bit snapshot");
            snapshots=snapshots+1;
        end else if(received!==previous_received) $fatal(1,"CDC bus changed without valid");
        previous_received=received;
        #1;
        if({hs_out,vs_out,de_out}!=={sampled_hs,sampled_vs,sampled_de}) $fatal(1,"RGB/sync pipeline misalignment");
        if(!de_out && rgb!==0) $fatal(1,"nonblack blanking");
        if(frame_count>=2 && py>=402 && py<=462 && (py-402)%20==0 && px>=18 && px<=378 && (px-18)%60==0) begin
            if(rgb !== (snapshot[256+((py-402)/20)*7+(px-18)/60] ? 24'h32d39a : 24'hd9e2ef))
                $fatal(1,"28 key cell wrong x=%0d y=%0d rgb=%h",px,py,rgb);
            key_pixels=key_pixels+1;
        end
        if(frame_count==4 && sampled_de) $fwrite(image_file,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);
        if(px==999 && py==499) begin
            if(pixels!=500000 || active_pixels!=384000 || hs_pixels!=36000 || vs_pixels!=7000)
                $fatal(1,"video geometry frame=%0d pixels=%0d active=%0d hs=%0d vs=%0d",frame_count,pixels,active_pixels,hs_pixels,vs_pixels);
            pixels=0;active_pixels=0;hs_pixels=0;vs_pixels=0;frame_count=frame_count+1;
            if(frame_count==6) begin
                $fclose(image_file);
                if(key_pixels!=112 || renderer.keys!==28'ha5c39e1 || snapshots<5 || renderer.shown==0 || renderer.peaks==0) $fatal(1,"snapshot/render coverage");
                $display("PASS video28: all 28 key cells x4 frames, 289bit CDC; frames=%0d snapshots=%0d 800x480 active, 1000x500 total, RGB/sync aligned",frame_count,snapshots);
                $finish;
            end
        end
    end
    initial begin
        #1;
        if(renderer.title_char(0)!=="2" || renderer.title_char(1)!=="8" || renderer.title_char(3)!=="K" || renderer.title_char(6)!=="S" || renderer.glyph("Y")==0)
            $fatal(1,"28 key title/font missing or truncated");
        image_file=$fopen("spectrum28_preview.ppm","w"); $fwrite(image_file,"P3\n800 480\n255\n");
        repeat(4) @(negedge clk); rst_n=1;
    end
    initial begin #110000000;$fatal(1,"video timeout");end
endmodule
