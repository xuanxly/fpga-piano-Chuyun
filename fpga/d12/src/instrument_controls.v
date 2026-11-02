`timescale 1ns/1ps
module instrument_controls #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BUTTON_CYCLES = CLK_HZ / 200, // 按钮消抖 5 ms
    parameter integer ENCODER_CYCLES = CLK_HZ / 1000, // 编码器滤波初值 1 ms，实物可调
    parameter integer ENABLE_TRANSPOSE_SET = 0, // 仅触摸工程允许绝对移调写入
    parameter integer ENABLE_TIMBRE_EFFECT=0, LONG_PRESS_CYCLES=CLK_HZ*2,
    parameter integer EDGES_PER_DETENT = 2 // EC11E15204A3：30 格/15 脉冲，每格两次相位转换
)(
    input wire clk, input wire rst_n,
    input wire enc_a, input wire enc_b, input wire dark_button_n,
    output reg signed [3:0] transpose,  // -5 到 +5 个半音
    output reg dark_mode,              // 0 正常，1 偏暗
    output reg [9:0] transpose_led,     // 十个灯只表示升降调量
    output wire dark_led,              // 可选明暗指示灯，高有效
    input wire transpose_set_valid,    // 一拍写入许可；同拍优先于机械旋钮
    input wire [2:0] timbre_select,output wire vibrato_enable,output wire [4:0] effect_state,
    input wire signed [3:0] transpose_set // 音调柱给出的绝对半音数，统一钳位到-5..+5
);
    wire a, b, button_n;
    debounce_bit #(.STABLE_CYCLES(ENCODER_CYCLES)) u_a(clk, rst_n, enc_a, a);
    debounce_bit #(.STABLE_CYCLES(ENCODER_CYCLES)) u_b(clk, rst_n, enc_b, b);
    debounce_bit #(.STABLE_CYCLES(BUTTON_CYCLES)) u_button(clk, rst_n, dark_button_n, button_n);
    // 每种音色记忆自己的短按状态；长按由原USB守卫处理，这里不重复触发短按。
    reg [4:0] effects;reg [31:0] press_count;reg press_armed;
    wire [2:0] selected=timbre_select<=4?timbre_select:3'd0;
    assign effect_state=effects;
    assign vibrato_enable=ENABLE_TIMBRE_EFFECT&&(selected==3||selected==4)&&effects[selected];
    reg [1:0] previous_ab;
    reg previous_button;
    reg signed [3:0] quarter_count;
    reg signed [3:0] delta;
    wire signed [4:0] accumulated =
        {quarter_count[3], quarter_count} + {delta[3], delta}; // 收集一个定位格所需的转换
    always @* begin
        case ({previous_ab, a, b})
            4'b0001, 4'b0111, 4'b1110, 4'b1000: delta = 4'sd1;
            4'b0010, 4'b1011, 4'b1101, 4'b0100: delta = -4'sd1;
            default: delta = 4'sd0;    // 跳过非法转换，避免触点跳变造成误计数
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            previous_ab <= 2'b11;
            previous_button <= 1'b1;
            quarter_count <= 0;
            transpose <= 0;
            dark_mode <= 0;effects<=0;press_count<=0;press_armed<=0;
        end else begin
            previous_button <= button_n;
            if(!ENABLE_TIMBRE_EFFECT)begin
                if(previous_button&&!button_n)dark_mode<=~dark_mode;
            end else begin
                dark_mode<=(selected==3||selected==4)?1'b0:effects[selected];
                if(previous_button&&!button_n)begin press_count<=0;press_armed<=1;end
                else if(!button_n&&press_armed&&press_count<LONG_PRESS_CYCLES)press_count<=press_count+1'b1;
                if(!previous_button&&button_n)begin
                    if(press_armed&&press_count<LONG_PRESS_CYCLES)effects[selected]<=~effects[selected];
                    press_armed<=0;
                end
            end
            if ({a,b} != previous_ab) begin
                previous_ab <= {a,b};
                if (delta == 0) quarter_count <= 0;
                else if (accumulated >= EDGES_PER_DETENT) begin
                    quarter_count <= 0;
                    if (transpose < 4'sd5) transpose <= transpose + 4'sd1;
                end else if (accumulated <= -EDGES_PER_DETENT) begin
                    quarter_count <= 0;
                    if (transpose > -4'sd5) transpose <= transpose - 4'sd1;
                end else quarter_count <= accumulated[3:0];
            end
            if (ENABLE_TRANSPOSE_SET && transpose_set_valid) begin
                // 两种输入共用唯一的transpose；松手后旋钮从当前值继续增减。
                transpose <= transpose_set > 4'sd5 ? 4'sd5 :
                             transpose_set < -4'sd5 ? -4'sd5 : transpose_set;
                quarter_count <= 0; // 清掉半格历史，避免触摸设值后残余边沿补计一格。
            end
        end
    end
    integer i;
    always @* begin
        transpose_led = 10'd0;
        for (i = 0; i < 5; i = i + 1) begin
            if ($signed(transpose) <= -(i+1)) transpose_led[4-i] = 1'b1; // 左边从中心向外
            if ($signed(transpose) >= (i+1)) transpose_led[5+i] = 1'b1;   // 右边从中心向外
        end
    end
    assign dark_led = ENABLE_TIMBRE_EFFECT?effects[selected]:dark_mode;
endmodule
