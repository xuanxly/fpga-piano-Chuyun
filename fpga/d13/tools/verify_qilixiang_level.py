"""用现有C解析器和实际游戏RTL验证新关卡；不访问开发板、TF卡或下载器。"""
from pathlib import Path
import ctypes as ct,hashlib,json,os,re,subprocess
from validate_song import validate

R=Path(__file__).resolve().parents[1];W=R/'reports/song_levels/QLX_EASY';W.mkdir(parents=True,exist_ok=True)
CSV=R/'tf_card/SONGS/QLX_EASY.CSV'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def main():
    data=validate(CSV)
    # 直接编译产品中使用的解析器，检查全部事件的时间、时长及28位琴键掩码。
    dll=W/'chart_parser.dll';gcc=Path('D:/msys64/ucrt64/bin/gcc.exe')
    os.environ['PATH']=str(gcc.parent)+os.pathsep+os.environ['PATH']
    compile_parser=subprocess.run([str(gcc),'-shared','-O2','-static-libgcc',str(R/'firmware/game_chart.c'),'-o',str(dll)],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace')
    (W/'compile_parser.log').write_text(compile_parser.stdout,encoding='utf-8')
    assert compile_parser.returncode==0,compile_parser.stdout
    class Parser(ct.Structure):_fields_=[('last',ct.c_uint32),('end',ct.c_uint32),('hold',ct.c_uint32*28),('notes',ct.c_uint32),('header',ct.c_uint)]
    class Event(ct.Structure):_fields_=[('time',ct.c_uint32),('mask',ct.c_uint32),('duration',ct.c_uint32)]
    lib=ct.CDLL(str(dll));lib.chart_reset.argtypes=[ct.POINTER(Parser)];lib.chart_line.argtypes=[ct.POINTER(Parser),ct.c_char_p,ct.POINTER(Event)];lib.chart_line.restype=ct.c_int
    p=Parser();lib.chart_reset(ct.byref(p));parsed=[]
    for line in CSV.read_text(encoding='ascii').splitlines():
        e=Event();status=lib.chart_line(ct.byref(p),line.encode('ascii'),ct.byref(e));assert status>=0,line
        if status==1:parsed.append((e.time,e.duration,e.mask))
    expected=json.loads((W/'chart_events.json').read_text(encoding='utf-8'))['events']
    for e,v in zip(expected,parsed):
        key=(int(e['note'][1])-3)*7+'CDEFGAB'.index(e['note'][0]);assert v==(e['time_ms'],e['duration_ms'],1<<key)
    assert len(parsed)==len(expected)==data['events'] and p.end==data['duration_ms']
    (W/'parser.log').write_text(f'PASS actual firmware chart_line: {p.notes} events, end={p.end}ms, all times/durations/masks exact\n',encoding='ascii')
    # 1个仿真时钟代表1ms，播放全关卡；CPU侧持续补队列，玩家按每个目标时刻按下并保持规定时长。
    # 音频合成不参与此加速测试；这里验证的是现有计时、同键再触发、长按和结算规则。
    service=(R/'firmware/game_service.inc').read_text(encoding='utf-8')
    assert 'hw_write(HW_GAME_TIME,chart.end+1)' in service
    end_at=p.end+1  # 与实际文件装载器使用相同的EOF时刻，不额外加宽结尾等待。
    bench='''`timescale 1ns/1ps
module tb_song_playthrough;
 localparam integer N=@COUNT@,END_AT=@END@;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,write=0;reg [5:0] address=0;reg [31:0] wdata=0;reg [27:0] keys=0;
 wire [31:0] rdata;wire [159:0] status;wire active;wire [27:0] guide,good,bad;
 game_engine28 #(.CLK_HZ(1000),.COUNTDOWN_MS(3)) dut(clk,rst_n,1'b1,keys,write,address,wdata,rdata,status,active,guide,good,bad);
 reg [31:0] times[0:N-1],durations[0:N-1],masks[0:N-1];
 integer idx,j,cycles=0;reg started=0;reg [27:0] wanted;
 task wr(input [5:0] a,input [31:0] d);begin
  @(negedge clk);write=1;address=a;wdata=d;@(negedge clk);write=0;
 end endtask
 task enqueue(input integer n);begin
  if(n<N)begin wr(4,times[n]);wr(8,masks[n]);wr(12,durations[n]);end
  else begin wr(4,END_AT);wr(8,32'h80000000);wr(12,0);end
  wr(16,1);
 end endtask
 initial begin
  $readmemh("times.hex",times);$readmemh("durations.hex",durations);$readmemh("masks.hex",masks);
  repeat(4)@(negedge clk);rst_n=1;wr(0,4);
  for(idx=0;idx<24&&idx<N;idx=idx+1)enqueue(idx);
  wr(0,1);started=1;
  while(idx<=N)begin wait(dut.count<24);enqueue(idx);idx=idx+1;end
 end
 always @(negedge clk)begin
  wanted=0;
  if(started&&dut.running&&dut.countdown==0)for(j=0;j<N;j=j+1)
   if(dut.now_ms>=times[j]&&dut.now_ms<times[j]+durations[j])wanted=wanted|masks[j];
  keys=wanted;
 end
 always @(posedge clk)if(rst_n&&started)begin
  cycles=cycles+1;#1;
  if(dut.fault||dut.misses!=0)$fatal(1,"Chart unplayable at%0dms hits%0d misses%0d",dut.now_ms,dut.hits,dut.misses);
  if(dut.complete)begin
   if(dut.hits!=N||dut.score!=N*100||dut.hold_mask!=0||dut.running||active||guide!=0)
    $fatal(1,"Incorrect final score/hit count or outputs");
   $display("PASS QLX_EASY actual game RTL: %0d/%0d hits,0 misses,score=%0d,all holds/repeated notes,queue refill,normal completion at%0dms",dut.hits,N,dut.score,dut.now_ms);$finish;
  end
  if(cycles>END_AT+4000)$fatal(1,"Chart completion timeout");
 end
 initial begin #2000000;$fatal(1,"Global chart timeout");end
endmodule
'''.replace('@COUNT@',str(data['events'])).replace('@END@',str(end_at))
    (W/'tb_song_playthrough.sv').write_text(bench,encoding='utf-8')
    bin=Path('D:/AMDDesignTools/2025.2/Vivado/bin')
    for program,args,name in [
        ('xvlog.bat',['-sv',str(R/'src/game_engine28.v'),str(W/'tb_song_playthrough.sv')],'compile.log'),
        ('xelab.bat',['tb_song_playthrough','-debug','off','-s','song_playthrough'],'elaborate.log'),
        ('xsim.bat',['song_playthrough','-runall'],'rtl_playthrough.log')]:
        run=subprocess.run([str(bin/program),*args],cwd=W,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,encoding='utf-8',errors='replace')
        (W/name).write_text(run.stdout,encoding='utf-8');assert run.returncode==0 and not re.search(r'^ERROR|^Fatal:|FATAL',run.stdout,re.M),f'{program}: see {W/name}'
    log=(W/'rtl_playthrough.log').read_text(encoding='utf-8');assert re.search(r'^PASS QLX_EASY',log,re.M)
    # 核对内容制作过程中产品输入未改变，D12原位流仍是925A。
    product=json.loads((R/'reports/d12_verification.json').read_text(encoding='utf-8'))
    for name,h in product['source_hashes'].items():assert sha(R/name)==h,name
    assert sha(R/'impl/pnr/pressure_piano_touch.fs')==product['bitstream_sha256']
    report={'status':'PASS_PARSER_AND_FULL_GAME_PLAYTHROUGH','chart':data,'csv_sha256':sha(CSV),
            'parser_source_sha256':sha(R/'firmware/game_chart.c'),'game_source_sha256':sha(R/'src/game_engine28.v'),
            'loader_source_sha256':sha(R/'firmware/game_service.inc'),'EOF_time_ms':end_at,'EOF_rule':'chart.end+1, same as actual firmware loader',
            'parser_log_sha256':sha(W/'parser.log'),'rtl_log_sha256':sha(W/'rtl_playthrough.log'),
            'D12_product_inputs_unchanged':True,'hardware_tested':False,'note':'Simulated perfect player;not human difficulty or board acceptance'}
    (W/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print((W/'parser.log').read_text().strip());print('\n'.join(re.findall(r'^PASS .*$',log,re.M)));print('PASS original D12 product inputs and bitstream unchanged')
if __name__=='__main__':main()
