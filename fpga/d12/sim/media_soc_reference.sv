`timescale 1ns/1ps
// 文件系统/解码处理器与乐器共用50MHz时钟，新增引脚只有原生TF卡的四路SPI。
module media_soc_reference #(
    parameter integer CLK_HZ=50000000,FIFO_WORDS=6144,ROM_WORDS=19456,RAM_WORDS=12288,
    parameter FIRMWARE="rom/media_firmware.hex"
)(
    input wire clk,rst_n,input wire [2:0] page,
    input wire command_valid,input wire [31:0] command,
    input wire record_valid,input wire signed [15:0] record_pcm,input wire sample_tick,
    output wire playback_exclusive,output wire signed [15:0] play_l,play_r,
    output reg [2175:0] ui_snapshot,output reg nav_valid,output reg [2:0] nav_page,
    output wire sd_cs_n,sd_sck,sd_mosi,input wire sd_miso,
    output reg [31:0] boot_status,
    input wire pixel_clk,display_bank,input wire [5:0] text_address,output wire [31:0] text_data
);
    wire icyc,istb,icyc_we,dcyc,dstb,dwe;
    wire [29:0] iadr,dadr;wire [31:0] iout,dout;wire [3:0] isel,dsel;
    reg iack,dack;reg [31:0] mmio_data;wire [31:0] rom_data,ram_data;wire [33:0] audio_data;
    wire [31:0] idata=rom_data;
    reg [1:0] data_source;reg audio_nonzero;
    wire [31:0] ddata=data_source==0?rom_data:data_source==1?ram_data:data_source==2?audio_data[31:0]:mmio_data;
    VexRiscv u_cpu(.clk(clk),.reset(!rst_n),.externalResetVector(32'd0),.timerInterrupt(1'b0),.softwareInterrupt(1'b0),.externalInterruptArray(32'd0),
        .iBusWishbone_CYC(icyc),.iBusWishbone_STB(istb),.iBusWishbone_ACK(iack),.iBusWishbone_WE(icyc_we),.iBusWishbone_ADR(iadr),
        .iBusWishbone_DAT_MISO(idata),.iBusWishbone_DAT_MOSI(iout),.iBusWishbone_SEL(isel),.iBusWishbone_ERR(1'b0),.iBusWishbone_CTI(),.iBusWishbone_BTE(),
        .dBusWishbone_CYC(dcyc),.dBusWishbone_STB(dstb),.dBusWishbone_ACK(dack),.dBusWishbone_WE(dwe),.dBusWishbone_ADR(dadr),
        .dBusWishbone_DAT_MISO(ddata),.dBusWishbone_DAT_MOSI(dout),.dBusWishbone_SEL(dsel),.dBusWishbone_ERR(1'b0),.dBusWishbone_CTI(),.dBusWishbone_BTE());
    wire base_request=dcyc&&dstb&&!dack;
    wire audio_wait;
    wire request=base_request&&!audio_wait;
    wire mmio=dadr[29:26]==4'hf;
    wire [15:0] offset={dadr[13:0],2'b00};
    wire write=request&&dwe&&mmio,read=request&&!dwe&&mmio;
    wire rom_d=request&&!mmio&&dadr<ROM_WORDS;
    wire rom_i=icyc&&istb&&!iack&&!rom_d;
    wire [14:0] rom_address=rom_d?dadr[14:0]:iadr[14:0];
    reg [31:0] milliseconds;reg [31:0] ms_count;
    reg [31:0] events[0:15];reg [3:0] event_w,event_r;reg [4:0] event_count;reg event_overflow;
    wire event_pop=read&&offset==12&&event_count!=0;
    wire event_push=command_valid&&event_count<16;
    reg [127:0] ui_staging;
    reg ui_bank,ui_accept;
    (* ASYNC_REG="TRUE",syn_keep=1 *)reg bank_meta,bank_seen;
    wire ui_busy=ui_bank!=bank_seen;
    wire text_write=write&&offset>=4096&&offset<4352&&((offset==4096)?!ui_busy:ui_accept);
    media_text_ram u_text(.cpu_clk(clk),.write(text_write),.waddr({!ui_bank,offset[7:2]}),.data(dout),
        .pixel_clk(pixel_clk),.raddr({display_bank,text_address}),.q(text_data));
    reg rec_enable,rec_pause,play_enable,play_pause,mode_play,rec_pending;
    reg [15:0] rec_first;reg [31:0] captured,played;
    reg [13:0] fifo_count,fifo_w,fifo_r;reg rec_overflow,play_underflow;
    wire rec_reset=write&&offset==16&&dout[2];
    wire play_reset=write&&offset==32&&dout[2]&&!rec_enable;
    wire fifo_reset=rec_reset||play_reset;
    wire rec_flush=write&&offset==16&&!dout[2]&&(!dout[0]||dout[1]);
    wire capture=record_valid&&rec_enable&&!rec_pause&&!rec_flush&&captured<32'd14400000&&!mode_play&&!rec_overflow;
    wire rec_push=!mode_play&&((capture&&rec_pending)||(rec_flush&&rec_pending))&&fifo_count<FIFO_WORDS;
    wire rec_pop=read&&offset==24&&!mode_play&&fifo_count!=0;
    wire play_push=write&&offset==40&&mode_play&&fifo_count<FIFO_WORDS;
    wire play_pop=sample_tick&&mode_play&&play_enable&&!play_pause&&page==5&&fifo_count!=0;
    wire push=rec_push||play_push,pop=rec_pop||play_pop;
    assign audio_wait=base_request&&mmio&&
        ((!dwe&&offset==24&&record_valid&&rec_enable&&!rec_pause&&rec_pending&&captured<14400000&&!mode_play&&!rec_overflow&&fifo_count<FIFO_WORDS)||
         (dwe&&offset==40&&sample_tick&&mode_play&&play_enable&&!play_pause&&page==5&&fifo_count!=0));
    assign playback_exclusive=play_enable&&page==5;
    assign play_l=audio_nonzero?audio_data[15:0]:16'd0;
    assign play_r=audio_nonzero?audio_data[31:16]:16'd0;
    function [13:0] next_ptr(input [13:0] p);begin next_ptr=p==FIFO_WORDS-1?0:p+1'b1;end endfunction

    reg [15:0] spi_div;reg spi_cs;
    wire spi_busy;wire [7:0] spi_byte;
    sd_spi_byte u_spi(.clk(clk),.rst_n(rst_n),.start(write&&offset==68&&!spi_busy),.tx(dout[7:0]),.half_div(spi_div),
        .busy(spi_busy),.rx(spi_byte),.sck(sd_sck),.mosi(sd_mosi),.miso(sd_miso));
    assign sd_cs_n=spi_cs;

    // 仲裁后的单口音频RAM：CPU端负责录音读出/播放写入；音频端负责录音写入/播放读出。
    // 不在复位时清整个RAM，以便综合为BSRAM；指针/计数复位即屏蔽所有旧内容。
    media_rom #(.WORDS(ROM_WORDS),.FIRMWARE(FIRMWARE)) u_rom(.clk(clk),.enable(rom_i||rom_d),.address(rom_address),.q(rom_data));
    media_ram #(.WORDS(RAM_WORDS)) u_ram(.clk(clk),.enable(request&&dadr[29:26]==4'h1&&dadr[25:0]<RAM_WORDS),
        .write(dwe),.address(dadr[13:0]),.data(dout),.bytes(dsel),.q(ram_data));
    media_audio_ram #(.WORDS(FIFO_WORDS)) u_audio(.clk(clk),.write(push&&!fifo_reset),.read(rec_pop||play_pop),.waddr(fifo_w),.raddr(fifo_r),
        .data(mode_play?{2'd2,dout}:{capture?2'd2:2'd1,capture?record_pcm:16'd0,rec_first}),.q(audio_data));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            iack<=0;
        end else begin
            iack<=rom_i;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            dack<=0;mmio_data<=0;data_source<=3;milliseconds<=0;ms_count<=0;event_w<=0;event_r<=0;event_count<=0;event_overflow<=0;
            rec_enable<=0;rec_pause<=0;play_enable<=0;play_pause<=0;mode_play<=0;rec_pending<=0;rec_first<=0;
            captured<=0;played<=0;fifo_count<=0;fifo_w<=0;fifo_r<=0;rec_overflow<=0;play_underflow<=0;
            audio_nonzero<=0;ui_staging<=0;ui_snapshot<=0;ui_bank<=0;ui_accept<=0;bank_meta<=0;bank_seen<=0;nav_valid<=0;nav_page<=0;boot_status<=0;
            spi_div<=64;spi_cs<=1;
        end else begin
            dack<=request;nav_valid<=0;bank_meta<=display_bank;bank_seen<=bank_meta;
            // 每个软件包从第0字开始；繁忙时整包拒绝，不让中途解除繁忙造成半包更新。
            if(write&&offset==4096)ui_accept<=!ui_busy;
            if(ms_count==CLK_HZ/1000-1) begin ms_count<=0;milliseconds<=milliseconds+1'b1;end else ms_count<=ms_count+1'b1;
            if(event_push) begin events[event_w]<=command;event_w<=event_w+1'b1;end
            if(command_valid&&!event_push)event_overflow<=1;
            if(event_pop)event_r<=event_r+1'b1;
            case({event_push,event_pop})2'b10:event_count<=event_count+1'b1;2'b01:event_count<=event_count-1'b1;default:begin end endcase
            if(page!=5)play_enable<=0; // 离开播放页立即恢复琴音，不依赖软件是否正忙于读卡。
            if(capture) begin
                captured<=captured+1'b1;
                if(!rec_pending)begin rec_first<=record_pcm;rec_pending<=1;end
                else rec_pending<=0;
            end
            if(rec_flush)rec_pending<=0;
            if((capture&&rec_pending||rec_flush&&rec_pending)&&fifo_count==FIFO_WORDS)begin rec_overflow<=1;rec_enable<=0;end
            if(sample_tick)begin
                audio_nonzero<=play_pop;
                if(play_pop)played<=played+1'b1;
                else if(play_enable&&!play_pause&&page==5&&mode_play&&fifo_count==0)play_underflow<=1;
            end
            if(push)fifo_w<=next_ptr(fifo_w);
            if(pop)fifo_r<=next_ptr(fifo_r);
            case({push,pop})2'b10:fifo_count<=fifo_count+1'b1;2'b01:fifo_count<=fifo_count-1'b1;default:begin end endcase
            if(write)case(offset)
                16:begin rec_enable<=dout[0];rec_pause<=dout[1];end
                32:if(!rec_enable)begin play_enable<=dout[0]&&page==5;play_pause<=dout[1];end
                64:begin spi_div<=dout[15:0]==0?16'd1:dout[15:0];spi_cs<=dout[16];end
                80:begin nav_valid<=1;nav_page<=dout[2:0];end
                84:if(ui_accept)begin ui_snapshot<={ui_staging,2047'd0,!ui_bank};ui_bank<=!ui_bank;ui_accept<=0;end
                88:boot_status<=dout;
                default:if(offset>=4352&&offset<4368&&ui_accept)ui_staging[(offset-4352)*8+:32]<=dout;
            endcase
            if(fifo_reset) begin
                fifo_count<=0;fifo_w<=0;fifo_r<=0;rec_pending<=0;rec_overflow<=0;play_underflow<=0;played<=0;captured<=0;
                rec_enable<=0;rec_pause<=0;play_enable<=0;play_pause<=0;mode_play<=play_reset;audio_nonzero<=0;
            end
            if(request)begin
                if(dadr<ROM_WORDS)data_source<=0;
                else if(dadr[29:26]==4'h1&&dadr[25:0]<RAM_WORDS)data_source<=1;
                else if(rec_pop)data_source<=2;
                else begin data_source<=3;if(mmio)case(offset)
                    0:mmio_data<=milliseconds;
                    4:mmio_data<={29'd0,page};
                    8:mmio_data<={23'd0,event_overflow,3'd0,event_count};
                    12:mmio_data<=event_count?events[event_r]:32'd0;
                    16:mmio_data<={30'd0,rec_pause,rec_enable};
                    20:mmio_data<={rec_overflow,17'd0,fifo_count};
                    24:mmio_data<=0; // 有效FIFO数据由独立同步RAM口和data_source=2返回。
                    28:mmio_data<=captured;
                    32:mmio_data<={30'd0,play_pause,play_enable};
                    36:mmio_data<=FIFO_WORDS-fifo_count;
                    44:mmio_data<=played;
                    48:mmio_data<={31'd0,play_underflow};
                    60:mmio_data<={30'd0,audio_data[33:32]};
                    72:mmio_data<={16'd0,spi_byte,7'd0,spi_busy};
                    88:mmio_data<=boot_status;
                    default:mmio_data<=0;
                endcase else mmio_data<=0;end
            end
        end
    end
endmodule

