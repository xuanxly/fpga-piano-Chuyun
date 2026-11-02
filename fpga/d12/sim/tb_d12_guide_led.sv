`timescale 1ns/1ps
module tb_d12_guide_led;
 reg clk=0;always #10 clk=~clk;reg rst_n=0,guide_active=1;
 reg [27:0] key_gate=0,guide_keys=28'h101,good_keys=1,bad_keys=28'h8000000;wire led;
 piano28_lights #(.ENABLE_GAME(1),.FRAME_CYCLES(225000)) d(.clk(clk),.rst_n(rst_n),.key_gate(key_gate),.guide_active(guide_active),
     .guide_keys(guide_keys),.good_keys(good_keys),.bad_keys(bad_keys),.led_data(led));
 integer frames=0,pixels=0;
 // PCB4四灯一键，四排蛇形；独立按行列计算，避免复制RTL的查找表。
 function integer owner(input integer pixel);
   integer group,row,col;begin group=pixel/4;row=group/7;col=group%7;owner=row*7+((row%2)==0?6-col:col);end
 endfunction
 task receive_frame(input integer mode);
   integer n,b,k;time rise_at,high_ns;reg [23:0] word,expected;
   begin
    @(posedge led);
    for(n=0;n<112;n++)begin
      word=0;
      for(b=23;b>=0;b--)begin
        rise_at=$time;@(negedge led);high_ns=$time-rise_at;
        if(high_ns!=320&&high_ns!=640)$fatal(1,"Guide pulse invalid");word={word[22:0],high_ns==640};
        if(n!=111||b!=0)@(posedge led);
      end
      k=owner(n);expected=0;
      if(mode==1)begin if(k==27)expected=24'h002000;else if(k==0)expected=24'h200000;else if(k==8)expected=24'h080020;end
      if(word!==expected)$fatal(1,"Guide mode%0d pixel%0d owner%0d got%h expected%h",mode,n,k,word,expected);
      pixels++;
    end
    frames++;
   end
 endtask
 initial begin
   #101;rst_n=1;receive_frame(0); // 第一个完整帧必须黑色
   receive_frame(1);guide_active=0;guide_keys=0;good_keys=0;bad_keys=0;
   receive_frame(0);
   if(frames!=3||pixels!=336)$fatal(1,"Incomplete guide frame coverage");
   $display("PASS D12 guide LEDs:336 real decoded GRB pixels,PCB4 serpentine mapping,good/next/wrong colors,blank boot,exit clear");$finish;
 end
 initial begin #16000000;$fatal(1,"Guide LED timeout");end
endmodule
