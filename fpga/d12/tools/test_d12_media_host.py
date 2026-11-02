from pathlib import Path
import subprocess,shutil,re,json,os
R=Path(__file__).resolve().parents[1];W=R/'reports/host_media';W.mkdir(exist_ok=True)
ff=Path(r'D:/Program Files/音视频转文字/ffmpeg.exe')
fixtures=[]
for name,opts in [('one.wav',['-ar','48000','-c:a','pcm_s16le']),('two.wav',['-ar','22050','-c:a','pcm_s16le'])]:
 p=W/name;subprocess.run([str(ff),'-hide_banner','-loglevel','error','-y','-f','lavfi','-i','sine=frequency=997:sample_rate=48000:duration=3','-af','pan=stereo|c0=c0|c1=0.6*c0']+opts+[str(p)],check=True);fixtures.append(str(p))
F=W/'fatfs';F.mkdir(exist_ok=True)
for n in ['ff.c','ff.h','ffconf.h','ffunicode.c','diskio.h']:shutil.copyfile(R/'third_party/fatfs'/n,F/n)
p=F/'ffconf.h';s=p.read_text(encoding='utf-8');s=re.sub(r'(#define\s+FF_USE_MKFS\s+)0',r'\g<1>1',s);p.write_text(s,encoding='utf-8')
src=[R/'sim/d12_media_host_test.c',R/'firmware/media_service.c',R/'firmware/game_chart.c',F/'ff.c',F/'ffunicode.c']
gcc=r'D:/msys64/ucrt64/bin/gcc.exe';exe=W/'media_test.exe'
os.environ['PATH']=str(Path(gcc).parent)+os.pathsep+os.environ['PATH']
args=[gcc,'-O2','-DUNICODE','-D_UNICODE','-DMEDIA_TEST_HOST','-fwrapv','-fno-strict-aliasing']+['-I'+str(p) for p in [R/'firmware',F,R/'third_party/helix/pub',R/'third_party/helix/real']]+list(map(str,src))+['-o',str(exe)]
subprocess.run(args,check=True)
for exfat in [1,0]:
 p=subprocess.run([str(exe),str(exfat)]+fixtures,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);(W/f'test_{exfat}.log').write_text(p.stdout,encoding='utf-8');print(p.stdout);assert p.returncode==0
