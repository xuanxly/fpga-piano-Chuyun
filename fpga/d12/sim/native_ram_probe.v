// 独立厂商网表测试顶层，没有开发板引脚约束，禁止用于开发板下载。
module mem_ram_probe(input wire clk,enable,write,input wire [13:0] address,
 input wire [33:0] data,input wire [3:0] bytes,output wire [31:0] ram_q,output wire [33:0] audio_q);
 media_ram #(.WORDS(12288)) work_ram(.clk(clk),.enable(enable),.write(write),.address(address),.data(data[31:0]),.bytes(bytes),.q(ram_q));
 wire valid=enable&&address<6144;
 media_audio_ram #(.WORDS(6144)) audio_ram(.clk(clk),.write(valid&&write),.read(valid&&!write),
  .waddr(address),.raddr(address),.data(data),.q(audio_q));
endmodule
