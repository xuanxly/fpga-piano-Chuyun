`timescale 1ns/1ps
// 仅用于仿真：依据 Microchip 图 6-1 模拟 SPI 时序，不加入 Gowin 工程。
module mcp3008_model (
    input wire cs_n, input wire sck, input wire mosi,
    input wire [79:0] channel_values,           // 八路模拟输入的十位数字替身
    output reg miso = 0,
    output integer transactions = 0
);
    integer edge_count = 0;
    reg [23:0] command = 0;
    reg [2:0] selected = 0;
    reg [9:0] value = 0;
    always @(negedge cs_n) begin edge_count=0; command=0; miso=0; end
    always @(posedge sck) if (!cs_n) begin
        command = {command[22:0], mosi};
        edge_count = edge_count + 1;
        if (edge_count < 8 && mosi) $fatal(1,"MCP3008 leading zeros are wrong");
        if (edge_count == 8 && !mosi) $fatal(1,"MCP3008 Start bit missing at clock 8");
        if (edge_count == 9 && !mosi) $fatal(1,"MCP3008 single-ended bit missing");
        if (edge_count == 12) selected = command[2:0]; // 从收到的命令解析通道
    end
    always @(negedge sck) if (!cs_n) begin
        if (edge_count == 13) value = channel_values[selected*10 +: 10]; // 模拟采样保持
        if (edge_count >= 14 && edge_count <= 23)
            miso <= #200 value[23-edge_count]; // 第 14 个下降沿推出 B9，后续依次推出 B0
        else miso <= #200 0;
    end
    always @(posedge cs_n) if (edge_count > 0) begin
        if (edge_count != 24) $fatal(1,"MCP3008 transaction must contain 24 clocks");
        if (command !== {8'h01,1'b1,selected,4'd0,8'h00}) $fatal(1,"MCP3008 command mismatch");
        transactions = transactions + 1;
    end
endmodule
