`timescale 1ns/1ps
// D7：两个USB数据位和输出使能同拍锁存；OEN触发器INIT=1，启动时直接保持高阻。
// allow必须来自已同步释放的会话复位；allow撤销可在USB时钟停止时异步关闭输出。
// 相对PHY原输出增加一个60MHz周期，USB原协议状态机与采样时钟均保持。
module usb_pad_pair_registered(
    input wire clk,allow,tx_enable,dp_tx,dm_tx,
    inout wire dp,dm,output wire dp_rx,dm_rx,drive
);
    (* syn_preserve=1 *) reg pad_oe_n=1'b1; // 高有效关闭；不依靠组合LUT计算默认关断值。
    (* syn_preserve=1 *) reg dp_tx_q=1'b0,dm_tx_q=1'b0;
    always @(posedge clk or negedge allow) begin
        if(!allow) begin
            pad_oe_n<=1'b1;dp_tx_q<=1'b0;dm_tx_q<=1'b0;
        end else begin
            pad_oe_n<=~tx_enable;dp_tx_q<=dp_tx;dm_tx_q<=dm_tx; // 数据和使能一起延迟，保持串行位宽。
        end
    end
    assign drive=~pad_oe_n; // 诊断显示实际锁存后的驱动状态。
    usb_pad_buffer u_dp(.pad(dp),.tx(dp_tx_q),.drive(drive),.rx(dp_rx));
    usb_pad_buffer u_dm(.pad(dm),.tx(dm_tx_q),.drive(drive),.rx(dm_rx));
endmodule
