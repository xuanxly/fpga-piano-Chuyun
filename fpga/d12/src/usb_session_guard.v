`timescale 1ns/1ps
// D4：USB主机与琴音/显示分别启动。配置完成后先高阻观察USB1，长按明暗键才允许发包。
// 看门狗使用50MHz系统时钟；USB时钟停止但LOCK仍为1时，也必须撤掉USB输出允许。
module usb_session_guard #(
    parameter integer ARM_CYCLES=100000000,      // 50MHz下连续按住2秒；每次按住仅切换一次。
    parameter integer WATCHDOG_CYCLES=100000,    // 2ms没有USB心跳，就停主机并释放触摸。
    parameter integer AUTOSTART=0               // 仅回归模型使用1；实板恢复版固定0。
)(
    input wire clk,rst_n,button_n,usb_lock,usb_heartbeat,
    output reg armed,output wire healthy,output reg watchdog_fault
);
    localparam integer AW=(ARM_CYCLES<2)?1:$clog2(ARM_CYCLES);
    localparam integer WW=(WATCHDOG_CYCLES<2)?1:$clog2(WATCHDOG_CYCLES+1);
    (* ASYNC_REG="TRUE",syn_preserve=1 *) reg key_meta,key_sync,lock_meta,lock_sync,beat_meta,beat_sync;
    reg beat_last,beat_seen,released,consumed,auto_started;
    reg [AW-1:0] hold_count;
    reg [WW-1:0] age;
    assign healthy=lock_sync && beat_seen && age<WATCHDOG_CYCLES;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            key_meta<=0;key_sync<=0;lock_meta<=0;lock_sync<=0;beat_meta<=0;beat_sync<=0;beat_last<=0;beat_seen<=0;age<=WATCHDOG_CYCLES;
            armed<=0;watchdog_fault<=0;hold_count<=0;released<=0;consumed<=0;auto_started<=0;
        end else begin
            key_meta<=button_n;key_sync<=key_meta;lock_meta<=usb_lock;lock_sync<=lock_meta;beat_meta<=usb_heartbeat;beat_sync<=beat_meta;
            beat_last<=beat_sync;
            if(!lock_sync) begin age<=WATCHDOG_CYCLES;beat_seen<=0;end
            else if(beat_last!=beat_sync) begin age<=0;beat_seen<=1;end
            else if(age<WATCHDOG_CYCLES) age<=age+1'b1;
            if(armed && !healthy) begin armed<=0;watchdog_fault<=1;end // 故障不自行重启，需重新长按。
            if(AUTOSTART && !auto_started && healthy) begin armed<=1;auto_started<=1;end
            if(key_sync) begin released<=1;hold_count<=0;consumed<=0;end
            else if(released && !consumed) begin
                if(hold_count==ARM_CYCLES-1) begin
                    consumed<=1;hold_count<=0;
                    if(armed) armed<=0;else if(healthy) begin armed<=1;watchdog_fault<=0;end
                end else hold_count<=hold_count+1'b1;
            end
        end
    end
endmodule
