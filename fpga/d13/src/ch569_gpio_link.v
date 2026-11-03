`timescale 1ns/1ps
// 使用板上既有HSPI连线作低速双向握手，不需要新硬件，也不依赖缺少RX的旧HSPI例程。
// MCU先发送带CRC的身份包；固件确认后才允许FPGA驱动HD5/6/7/12。身份未确认时数据脚保持高阻。
module ch569_gpio_link(
    input wire clk,rst_n,allow_tx,
    input wire mcu_ready,mcu_rx_req,mcu_tx_ack,input wire [3:0] mcu_data,
    output reg fpga_rx_ack,fpga_tx_req,output reg [3:0] fpga_data,output wire data_oe_n,
    input wire rx_pop,output wire [7:0] rx_data,output wire [9:0] rx_count,
    input wire tx_push,input wire [7:0] tx_data,output wire [9:0] tx_free,
    input wire clear,output wire ready
);
    (* ASYNC_REG="TRUE",syn_keep=1 *) reg [1:0] ready_s,req_s,ack_s;
    // INIT=1且异步关断的单级OEN寄存器，禁止组合逻辑直接驱动输出使能。
    (* syn_keep=1,syn_preserve=1 *) reg pad_oe_n=1;
    wire pad_reset_n=rst_n&&mcu_ready;
    always @(posedge clk or negedge pad_reset_n)if(!pad_reset_n)pad_oe_n<=1;else pad_oe_n<=!allow_tx;
    assign data_oe_n=pad_oe_n;
    assign ready=ready_s[1];
    (* syn_ramstyle="block_ram" *) reg [7:0] rx_mem[0:511],tx_mem[0:511];
    reg [8:0] rw,rr,tw,tr;reg [9:0] rc,tc;reg [7:0] rq,tq,send_byte;
    reg half;reg [3:0] low_nibble;reg [2:0] tx_state;reg [1:0] rx_settle;
    wire rx_pending=req_s[1]!=fpga_rx_ack;
    wire receive=ready&&rx_pending&&rx_settle==2&&rc<512;
    wire rx_push=receive&&half;
    wire pop=rx_pop&&rc!=0;
    wire push=tx_push&&tc<512&&allow_tx;
    wire sent=tx_state==4&&ack_s[1]==fpga_tx_req;
    assign rx_data=rq;assign rx_count=rc;assign tx_free=512-tc;
    always @(posedge clk)begin
        rq<=rx_mem[rr];tq<=tx_mem[tr];
        if(rx_push)rx_mem[rw]<={mcu_data,low_nibble};
        if(push)tx_mem[tw]<=tx_data;
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            ready_s<=0;req_s<=0;ack_s<=0;fpga_rx_ack<=0;fpga_tx_req<=0;fpga_data<=0;
            rw<=0;rr<=0;tw<=0;tr<=0;rc<=0;tc<=0;half<=0;low_nibble<=0;send_byte<=0;tx_state<=0;rx_settle<=0;
        end else begin
            ready_s<={ready_s[0],mcu_ready};req_s<={req_s[0],mcu_rx_req};ack_s<={ack_s[0],mcu_tx_ack};
            if(rx_pending)begin if(rx_settle!=2)rx_settle<=rx_settle+1'b1;end else rx_settle<=0;
            if(receive)begin
                if(!half)low_nibble<=mcu_data;
                half<=~half;fpga_rx_ack<=req_s[1];rx_settle<=0;
            end
            case({rx_push,pop})2'b10:rc<=rc+1'b1;2'b01:rc<=rc-1'b1;default:begin end endcase
            case({push,sent})2'b10:tc<=tc+1'b1;2'b01:tc<=tc-1'b1;default:begin end endcase
            if(rx_push)rw<=rw+1'b1;if(pop)rr<=rr+1'b1;
            if(push)tw<=tw+1'b1;if(sent)tr<=tr+1'b1;
            case(tx_state)
                0:if(tc!=0&&allow_tx&&!pad_oe_n)tx_state<=6;
                6:begin send_byte<=tq;fpga_data<=tq[3:0];tx_state<=1;end // 首次入队也等待同步RAM预取完成
                1:begin fpga_tx_req<=~fpga_tx_req;tx_state<=2;end // 数据比req提前一拍
                2:if(ack_s[1]==fpga_tx_req)begin fpga_data<=send_byte[7:4];tx_state<=3;end
                3:begin fpga_tx_req<=~fpga_tx_req;tx_state<=4;end
                4:if(sent)tx_state<=5;
                5:tx_state<=0; // 等待同步RAM预取新的队首
                default:tx_state<=0;
            endcase
            if(clear||!ready_s[1])begin
                rw<=0;rr<=0;tw<=0;tr<=0;rc<=0;tc<=0;half<=0;tx_state<=0;rx_settle<=0;
                fpga_rx_ack<=0;fpga_tx_req<=0;
            end
        end
    end
endmodule
