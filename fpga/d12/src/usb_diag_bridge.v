`timescale 1ns/1ps
// USB域诊断用握手快照跨到50MHz域；数据保持至应答，不能逐位同步多位状态码。
// C标记通过快照更新来判断USB时钟是否工作；L/R独立同步，便于辨别PLL未锁定或USB复位未释放。
module usb_diag_bridge #(parameter integer STALE_CYCLES=5000000)(
    input wire usb_clk,usb_rst_n,input wire [63:0] usb_info,
    input wire usb_lock,report_error,input wire sys_clk,sys_rst_n,
    output wire [71:0] diagnostic
);
    wire [63:0] received;wire valid;
    spectrum_cdc #(.WIDTH(64)) u_cdc(.src_clk(usb_clk),.src_rst_n(usb_rst_n),.src_data(usb_info),
        .dst_clk(sys_clk),.dst_rst_n(sys_rst_n),.dst_frame(1'b1),.dst_data(received),.dst_valid(valid));
    (* ASYNC_REG="TRUE",syn_preserve=1 *) reg lock_meta,lock_seen,reset_meta,reset_seen,error_meta,error_seen;
    reg [22:0] age;reg live;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n) begin lock_meta<=0;lock_seen<=0;reset_meta<=0;reset_seen<=0;error_meta<=0;error_seen<=0;age<=0;live<=0;end
        else begin
            lock_meta<=usb_lock;lock_seen<=lock_meta;reset_meta<=usb_rst_n;reset_seen<=reset_meta;error_meta<=report_error;error_seen<=error_meta;
            if(valid) begin age<=0;live<=1;end
            else if(age<STALE_CYCLES) age<=age+1'b1;
            else live<=0;
        end
    end
    assign diagnostic={4'd0,error_seen,reset_seen,lock_seen,live,received};
endmodule
