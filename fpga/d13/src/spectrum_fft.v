`timescale 1ns/1ps
// 原创 HDL 实现；显示构思参考 HACK实验室 hack_spectrum_v1.0，出处见 docs/SPECTRUM.md。
module spectrum_fft (
    input wire clk, input wire rst_n,
    input wire pcm_valid, input wire signed [15:0] pcm,
    output reg frame_valid, output reg [255:0] levels, // 32 个频段，每段八位对数幅度
    output reg overrun,                                // 仅报告频谱处理超时，绝不阻塞音频
    output reg bin_valid, output reg [9:0] bin_index,
    output reg signed [17:0] bin_real, bin_imag        // 数值自检接口，整机未使用时由综合裁剪
);
    reg signed [15:0] capture_mem [0:4095];            // 双缓冲，连续保存 48 kHz 原始 PCM
    reg [35:0] fft_mem [0:2047];                      // 原位复数 RAM：实部十八位、虚部十八位
    reg signed [15:0] window_rom [0:2047];            // Q1.15 Hamming 窗
    reg [31:0] twiddle_rom [0:1023];                  // Q1.15 cos 与负 sin，正向 FFT
    initial begin
        $readmemh("rom/spectrum_window.hex", window_rom);
        $readmemh("rom/spectrum_twiddle.hex", twiddle_rom);
    end
    reg capture_bank, done_bank, work_bank, capture_done;
    reg [10:0] capture_index, load_index;
    reg signed [27:0] sample_sum;
    reg signed [16:0] frame_mean, work_mean;
    wire signed [27:0] final_sum = sample_sum + pcm;  // 包括最后一个采样，再计算整帧均值
    always @(posedge clk) begin
        if (pcm_valid) capture_mem[{capture_bank,capture_index}] <= pcm;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            capture_bank<=0; done_bank<=0; capture_index<=0; sample_sum<=0;
            frame_mean<=0; capture_done<=0;
        end else begin
            capture_done<=0;
            if (pcm_valid) begin
                if (capture_index==2047) begin
                    capture_index<=0; done_bank<=capture_bank; capture_bank<=~capture_bank;
                    frame_mean<=final_sum >>> 11; sample_sum<=0; capture_done<=1;
                end else begin capture_index<=capture_index+1'b1; sample_sum<=final_sum; end
            end
        end
    end
    localparam IDLE=0, LOAD_REQ=1, LOAD_WAIT=2, LOAD_MUL=3, LOAD_STORE=4,
        READ_A=5, WAIT_A=6, READ_B=7, WAIT_B=8, MULT=9, MULT_ADD=10,
        BUTTERFLY=11, WRITE_A=12, WRITE_B=13, ADVANCE=14,
        SCAN_REQ=15, SCAN_WAIT=16, SCAN_ACC=17, PUBLISH=18, SCAN_LEVEL=19;
    reg [4:0] state;
    reg [3:0] stage;
    reg [10:0] half_size, block_base, butterfly_j, scan_index;
    wire [10:0] address_a=block_base+butterfly_j;
    wire [10:0] address_b=address_a+half_size;
    wire [9:0] twiddle_index=butterfly_j << (10-stage);
    reg signed [15:0] capture_q, window_q;
    reg [31:0] twiddle_q;
    always @(posedge clk) begin
        capture_q<=capture_mem[{work_bank,load_index}];
        window_q<=window_rom[load_index];
        twiddle_q<=twiddle_rom[twiddle_index];
    end
    function [10:0] reverse11;
        input [10:0] value;
        integer k;
        begin for(k=0;k<11;k=k+1) reverse11[k]=value[10-k]; end
    endfunction
    reg [10:0] ram_address;
    reg ram_write;
    reg [35:0] ram_d, ram_q;
    reg signed [32:0] window_product;
    wire signed [17:0] window_value=window_product >>> 15;
    reg signed [17:0] ar, ai, br, bi, out_ar, out_ai, out_br, out_bi;
    reg signed [33:0] rr, ii, ri, ir;
    wire signed [34:0] product_real=$signed({rr[33],rr})-$signed({ii[33],ii});
    wire signed [34:0] product_imag=$signed({ri[33],ri})+$signed({ir[33],ir});
    reg signed [19:0] rotated_real, rotated_imag;
    always @* begin
        ram_address=address_a; ram_write=0; ram_d=0;
        case(state)
            LOAD_STORE: begin ram_address=reverse11(load_index); ram_write=1; ram_d={window_value,18'd0}; end
            READ_B,WAIT_B: ram_address=address_b;
            WRITE_A: begin ram_write=1; ram_d={out_ar,out_ai}; end
            WRITE_B: begin ram_address=address_b; ram_write=1; ram_d={out_br,out_bi}; end
            SCAN_REQ,SCAN_WAIT,SCAN_ACC: ram_address=scan_index;
            default: begin end
        endcase
    end
    always @(posedge clk) begin
        if (ram_write) fft_mem[ram_address]<=ram_d;
        ram_q<=fft_mem[ram_address];                 // 同步读写，允许推断为片上 BSRAM
    end
    reg [4:0] band;
    reg [18:0] band_max;
    reg [18:0] pending_magnitude;                  // 打断 BSRAM→绝对值→对数高度的长路径
    reg [255:0] next_levels;
    wire signed [17:0] scan_r=ram_q[35:18], scan_i=ram_q[17:0];
    wire [17:0] abs_r=scan_r[17] ? -scan_r : scan_r;
    wire [17:0] abs_i=scan_i[17] ? -scan_i : scan_i;
    wire [18:0] magnitude={1'b0,abs_r}+{1'b0,abs_i}; // L1 幅度近似；不冒充校准声压或精确 dB
    wire [18:0] selected_max=(magnitude>band_max) ? magnitude : band_max;
    // 边界由 tools/spectrum_reference.py 生成；48 kHz / 2048 = 23.4375 Hz/bin。
    function [10:0] band_edge;
        input [5:0] index;
        begin
            case(index)
                6'd0: band_edge=11'd1;
6'd1: band_edge=11'd2;
6'd2: band_edge=11'd3;
6'd3: band_edge=11'd4;
6'd4: band_edge=11'd5;
6'd5: band_edge=11'd6;
6'd6: band_edge=11'd7;
6'd7: band_edge=11'd8;
6'd8: band_edge=11'd9;
6'd9: band_edge=11'd10;
6'd10: band_edge=11'd11;
6'd11: band_edge=11'd12;
6'd12: band_edge=11'd13;
6'd13: band_edge=11'd16;
6'd14: band_edge=11'd19;
6'd15: band_edge=11'd24;
6'd16: band_edge=11'd29;
6'd17: band_edge=11'd36;
6'd18: band_edge=11'd45;
6'd19: band_edge=11'd55;
6'd20: band_edge=11'd68;
6'd21: band_edge=11'd84;
6'd22: band_edge=11'd104;
6'd23: band_edge=11'd128;
6'd24: band_edge=11'd158;
6'd25: band_edge=11'd195;
6'd26: band_edge=11'd241;
6'd27: band_edge=11'd297;
6'd28: band_edge=11'd367;
6'd29: band_edge=11'd454;
6'd30: band_edge=11'd560;
6'd31: band_edge=11'd692;
6'd32: band_edge=11'd854;
                default: band_edge=854;
            endcase
        end
    endfunction
    function [7:0] amplitude_height;
        input [18:0] value;
        integer k, msb, fraction, height;
        begin
            msb=0;
            for(k=0;k<19;k=k+1) if(value[k]) msb=k;
            fraction=(msb>=4) ? ((value >> (msb-4)) & 15) : ((value << (4-msb)) & 15);
            height=((msb*16+fraction)-32)*2;       // 低于约四个量化单位的噪底不显示
            if(value<4 || height<0) amplitude_height=0;
            else if(height>255) amplitude_height=255;
            else amplitude_height=height[7:0];
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; load_index<=0; work_bank<=0; work_mean<=0;
            stage<=0; half_size<=1; block_base<=0; butterfly_j<=0; scan_index<=1;
            ar<=0; ai<=0; br<=0; bi<=0; rr<=0; ii<=0; ri<=0; ir<=0;
            rotated_real<=0; rotated_imag<=0; out_ar<=0; out_ai<=0; out_br<=0; out_bi<=0;
            window_product<=0; band<=0; band_max<=0; pending_magnitude<=0; next_levels<=0;
            levels<=0; frame_valid<=0; overrun<=0; bin_valid<=0; bin_index<=0; bin_real<=0; bin_imag<=0;
        end else begin
            frame_valid<=0; bin_valid<=0;
            if(capture_done && state!=IDLE) overrun<=1; // 可见诊断，音频采集继续运行
            case(state)
                IDLE: if(capture_done) begin
                    work_bank<=done_bank; work_mean<=frame_mean; load_index<=0; state<=LOAD_REQ;
                end
                LOAD_REQ: state<=LOAD_WAIT;
                LOAD_WAIT: state<=LOAD_MUL;
                LOAD_MUL: begin
                    window_product<=($signed({capture_q[15],capture_q})-work_mean)*window_q;
                    state<=LOAD_STORE;
                end
                LOAD_STORE: if(load_index==2047) begin
                    stage<=0; half_size<=1; block_base<=0; butterfly_j<=0; state<=READ_A;
                end else begin load_index<=load_index+1'b1; state<=LOAD_REQ; end
                READ_A: state<=WAIT_A;
                WAIT_A: begin ar<=ram_q[35:18]; ai<=ram_q[17:0]; state<=READ_B; end
                READ_B: state<=WAIT_B;
                WAIT_B: begin br<=ram_q[35:18]; bi<=ram_q[17:0]; state<=MULT; end
                MULT: begin
                    rr<=br*$signed(twiddle_q[31:16]); ii<=bi*$signed(twiddle_q[15:0]);
                    ri<=br*$signed(twiddle_q[15:0]); ir<=bi*$signed(twiddle_q[31:16]); state<=MULT_ADD;
                end
                MULT_ADD: begin rotated_real<=product_real >>> 15; rotated_imag<=product_imag >>> 15; state<=BUTTERFLY; end
                BUTTERFLY: begin
                    out_ar<=($signed(ar)+rotated_real) >>> 1; out_ai<=($signed(ai)+rotated_imag) >>> 1;
                    out_br<=($signed(ar)-rotated_real) >>> 1; out_bi<=($signed(ai)-rotated_imag) >>> 1;
                    state<=WRITE_A;                       // 每一级除二，总归一化为 1/2048
                end
                WRITE_A: state<=WRITE_B;
                WRITE_B: state<=ADVANCE;
                ADVANCE: begin
                    if(butterfly_j+1<half_size) begin butterfly_j<=butterfly_j+1'b1; state<=READ_A; end
                    else begin
                        butterfly_j<=0;
                        if(block_base+{half_size,1'b0}<2048) begin block_base<=block_base+{half_size,1'b0}; state<=READ_A; end
                        else if(stage<10) begin stage<=stage+1'b1; half_size<=half_size<<1; block_base<=0; state<=READ_A; end
                        else begin scan_index<=1; band<=0; band_max<=0; next_levels<=0; state<=SCAN_REQ; end
                    end
                end
                SCAN_REQ: state<=SCAN_WAIT;
                SCAN_WAIT: state<=SCAN_ACC;
                SCAN_ACC: begin
                    bin_valid<=1; bin_index<=scan_index[9:0]; bin_real<=scan_r; bin_imag<=scan_i;
                    if(scan_index<854) begin
                        if(scan_index+1==band_edge({1'b0,band}+1'b1)) begin
                            pending_magnitude<=selected_max; band_max<=0;
                        end else band_max<=selected_max;
                    end
                    if(scan_index<854 && scan_index+1==band_edge({1'b0,band}+1'b1)) state<=SCAN_LEVEL;
                    else if(scan_index==1023) state<=PUBLISH;
                    else begin scan_index<=scan_index+1'b1; state<=SCAN_REQ; end
                end
                SCAN_LEVEL: begin
                    next_levels[band*8 +: 8]<=amplitude_height(pending_magnitude);
                    if(band!=31) band<=band+1'b1;
                    scan_index<=scan_index+1'b1; state<=SCAN_REQ; // 每帧仅增加32个系统周期
                end
                PUBLISH: begin levels<=next_levels; frame_valid<=1; state<=IDLE; end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
