`timescale 1ns/1ps
// 对照原游戏判定器逐拍比较，覆盖命中、漏音、长音、暂停、清空及同拍冲突。
module tb_d12_game_timing;
 reg clk=0;always #5 clk=~clk;reg rst_n=0,page_active=1,write=0;reg [27:0] keys=0;reg [5:0] address=0;reg [31:0] wdata=0;
 wire [31:0] ra,rb;wire [159:0] sa,sb;wire ga,gb;wire [27:0] ka,kb,gooda,goodb,bada,badb;
 game_engine28 #(.CLK_HZ(1000),.COUNTDOWN_MS(3)) n(clk,rst_n,page_active,keys,write,address,wdata,ra,sa,ga,ka,gooda,bada);
 d12_game_timing_reference #(.CLK_HZ(1000),.COUNTDOWN_MS(3)) o(clk,rst_n,page_active,keys,write,address,wdata,rb,sb,gb,kb,goodb,badb);
 reg [31:0] seed=32'hdc45312a;integer checks=0,hits_seen=0,miss_seen=0,late_seen=0;
 function [31:0] rnd;begin seed=seed^(seed<<13);seed=seed^(seed>>17);seed=seed^(seed<<5);rnd=seed;end endfunction
 task check;begin #1;
 if(n.count!=0)begin
  if(n.head_time!==n.queue[n.rp][18:0]||
     n.head_begin!==(n.queued_time>150?n.queued_time-19'd150:19'd0)||
     n.head_end!==n.queued_time+19'd150||
     n.head_guide!==(n.queued_time>150?n.queued_time-19'd150:19'd0)||
     n.head_perfect_begin!==(n.queued_time>50?n.queued_time-19'd50:19'd0)||
     n.head_perfect_end!==n.queued_time+19'd50)$fatal(1,"Cached queue head differs from current queue event");
 end
 if({n.window_open_q,n.window_not_late_q,n.perfect_open_q,n.perfect_not_late_q,n.guide_due_q,n.cur_due_q,n.time_limit_q}!==
    {n.now_ms>=n.window_begin,n.now_ms<=n.window_end,n.now_ms>=n.perfect_begin,n.now_ms<=n.perfect_end,n.now_ms>=n.guide_begin,n.now_ms>=n.cur_time,n.now_ms>=19'd300500})$fatal(1,"Game time predictor did not match committed state");
 for(integer h=0;h<28;h++)if(n.hold_done_q[h] !== (n.now_ms>=n.hold_end[h]) || n.hold_early_q[h] !== (n.now_ms<n.hold_early_end[h]))$fatal(1,"Hold predictor mismatch key%0d",h);
 if({ra,sa,ga,ka,gooda,bada}!={rb,sb,gb,kb,goodb,badb}||{n.hit_mask,n.hold_mask,n.flash_ms,n.valid,n.now_ms,n.score,n.misses,n.hits}!={o.hit_mask,o.hold_mask,o.flash_ms,o.valid,o.now_ms,o.score,o.misses,o.hits})$fatal(1,"Game timing mismatch at%0d",checks);
 if(o.running&&!o.paused&&o.countdown==0&&o.valid&&!o.cur_end&&!o.practice&&o.now_ms>o.window_end)late_seen++;
 if(n.chord_hit&&n.late_miss)$fatal(1,"Hit and late miss were not exclusive");checks++;
 end endtask
 task cycle;begin @(negedge clk);check();end endtask
 task wr(input [5:0] a,input [31:0] v);begin write=1;address=a;wdata=v;cycle();write=0;cycle();end endtask
 initial begin
 repeat(4)cycle();rst_n=1;cycle();
 for(integer round=0;round<80;round++)begin
  keys=0;wr(0,round[0]?12:4);wr(0,round[0]?9:1);
  for(integer ev=0;ev<8;ev++)begin
   wr(4,40+ev*120);wr(8,(28'd1<<(ev%28))|(ev[0]?28'd1<<((ev+1)%28):0));wr(12,ev[1]?600:80);wr(16,1);
  end
  wr(4,2000);wr(8,32'h80000000);wr(12,0);wr(16,1);
  for(integer t=0;t<2600;t++)begin
   if(round%4==0)keys=28'h8000000;
   else if(t%13==0)keys=o.cur_mask;
   else if(t%17==0)keys=28'd1<<(rnd()%28);
   else if(t%11==0)keys=0;
   if(t==650)wr(0,round[0]?11:3);
   if(t==670)wr(0,round[0]?9:1);
   cycle();
  end
  hits_seen+=o.hits;miss_seen+=o.misses;
 end
 if(hits_seen<20||miss_seen<20||late_seen<20)$fatal(1,"Insufficient game coverage hits%0d miss%0d",hits_seen,miss_seen);
 $display("PASS D12 game timing:%0d exact cycles,hits%0d misses%0d late%0d,all63 predicted comparisons equal committed state",checks,hits_seen,miss_seen,late_seen);$finish;
 end
 initial begin #100000000;$fatal(1,"Game timing equivalence timeout");end
endmodule
