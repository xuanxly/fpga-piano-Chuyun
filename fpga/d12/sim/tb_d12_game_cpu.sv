`timescale 1ns/1ps
// 实际RV32固件接实际游戏MMIO；只强制准备运行状态，检查真实CPU发出的控制字。
module tb_d12_game_cpu;
 reg clk=0;always #10 clk=~clk;reg rst_n=0,command_valid=0;reg [31:0] command=0;
 wire [2175:0] ui_snapshot;wire [31:0] boot_status;integer writes=0;reg [31:0] captured;
 media_soc d(.clk(clk),.rst_n(rst_n),.page(3'd7),.keys(28'd0),.command_valid(command_valid),.command(command),
   .record_valid(1'b0),.record_pcm(16'd0),.sample_tick(1'b0),.sd_miso(1'b1),
   .ch_ready(1'b0),.ch_rx_req(1'b0),.ch_tx_ack(1'b0),.ch_rx_data(4'd0),
   .pixel_clk(clk),.display_bank(ui_snapshot[0]),.text_address(6'd0),.ui_snapshot(ui_snapshot),.boot_status(boot_status));
 always @(posedge clk)if(d.game_write_q&&d.game_address_q==0)begin captured<=d.game_wdata_q;writes<=writes+1;end
 task pause_command(input [31:0] expected);
   integer before_writes;
   begin
     before_writes=writes;@(negedge clk);command=32'h11000000;command_valid=1;
     @(negedge clk);command_valid=0;wait(writes>before_writes);@(negedge clk);
     if(captured!==expected||captured[2])$fatal(1,"Actual CPU pause write%h expected%h (clear bit must stay0)",captured,expected);
   end
 endtask
 initial begin
   #101;rst_n=1;wait(boot_status==32'hd9000001);wait(ui_snapshot[2069:2064]==1);repeat(200)@(negedge clk);
   force d.u_game.running=1;force d.u_game.practice=1;
   pause_command(11);if(!d.u_game.paused)$fatal(1,"Practice did not pause");
   pause_command(9);if(d.u_game.paused)$fatal(1,"Practice did not resume");
   force d.u_game.practice=0;
   pause_command(3);pause_command(1);
   release d.u_game.running;release d.u_game.practice;
   $display("PASS D12 actual CPU game MMIO: practice/challenge pause+resume preserve mode and never clear score/queue");$finish;
 end
 initial begin #10000000;$fatal(1,"Game CPU control timeout boot%h pc%h",boot_status,d.u_cpu.IBusCachedPlugin_fetchPc_pc);end
endmodule
