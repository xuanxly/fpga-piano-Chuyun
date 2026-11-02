`timescale 1ns/1ps
module voice_allocator (
    input wire clk, input wire rst_n, input wire sample_tick,
    input wire [6:0] key_gate,                 // 七键当前按下状态
    input wire [3:0] voice_active,             // 包含已经松键的释放尾音
    output reg [3:0] voice_gate,               // 四声部各自的持键状态
    output reg [3:0] note_start,               // 每个新分配事件只持续一个系统周期
    output reg [11:0] voice_key                // 四个三位归属，7 表示未分配
);
    reg [6:0] previous_keys, pending_keys;     // 上一帧状态和本帧新按下的键
    reg [2:0] scan_key;                       // 分七个系统周期处理七键，避免级联长组合路径
    reg busy;
    reg [2:0] chosen;
    integer v;
    always @* begin
        chosen = 3'd4;                       // 4 为无可用声部，不产生分配
        if (!voice_gate[0] && !voice_active[0]) chosen=0;
        else if (!voice_gate[1] && !voice_active[1]) chosen=1;
        else if (!voice_gate[2] && !voice_active[2]) chosen=2;
        else if (!voice_gate[3] && !voice_active[3]) chosen=3; // 优先完全空闲的声部
        else if (!voice_gate[0]) chosen=0;
        else if (!voice_gate[1]) chosen=1;
        else if (!voice_gate[2]) chosen=2;
        else if (!voice_gate[3]) chosen=3;    // 再复用已松键、尚在释放的声部
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            previous_keys<=0; pending_keys<=0; scan_key<=0; busy<=0;
            voice_gate<=0; note_start<=0; voice_key<={4{3'd7}};
        end else begin
            note_start<=0;                   // 每个声部的起音事件只占一个时钟
            if (sample_tick) begin
                previous_keys<=key_gate;
                pending_keys<=key_gate & ~previous_keys; // 忽略的第五键也记为已按下，须松开重按
                scan_key<=0; busy<=1;
                for (v=0;v<4;v=v+1) begin
                    if (voice_key[v*3 +: 3]<7) voice_gate[v]<=key_gate[voice_key[v*3 +: 3]];
                    else voice_gate[v]<=0;   // 松开只作用于当前归属于该键的声部
                end
            end else if (busy) begin
                if (pending_keys[scan_key]) begin
                    // 使用固定字段，避免动态字段下标乘法产生不必要的 DSP。
                    case (chosen)
                        0: begin voice_key[2:0]<=scan_key; voice_gate[0]<=1; note_start[0]<=1; end
                        1: begin voice_key[5:3]<=scan_key; voice_gate[1]<=1; note_start[1]<=1; end
                        2: begin voice_key[8:6]<=scan_key; voice_gate[2]<=1; note_start[2]<=1; end
                        3: begin voice_key[11:9]<=scan_key; voice_gate[3]<=1; note_start[3]<=1; end
                        default: begin end  // 四个都被按住时，该新键不抢占任何声部
                    endcase
                end
                if (scan_key==6) busy<=0;
                else scan_key<=scan_key+1'b1; // 在两个 48 kHz 采样点之间完成，最多约 140 ns
            end
        end
    end
endmodule
