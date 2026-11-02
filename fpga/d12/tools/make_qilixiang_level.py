"""把用户简谱的入门改编数据转换为D12谱面；只生成关卡和预听资料，不改HDL或位流。"""
from pathlib import Path
from fractions import Fraction
import hashlib,json,wave
from validate_song import validate

R=Path(__file__).resolve().parents[1]
SRC=R/'tf_card/chart_sources/QLX_EASY.json'
OUT=R/'tf_card/SONGS/QLX_EASY.CSV'
REPORT=R/'reports/song_levels/QLX_EASY'
DELIVERY=R/'reports/song_levels/QLX_EASY'

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def degree_note(degree):
    # 简谱不带点的1放在C4；上方一点放在C5，符合现有中间两排琴键。
    if degree=='0':return None
    octave=5 if degree.startswith('^') else 4
    digit=int(degree.lstrip('^'));assert 1<=digit<=7
    return 'CDEFGAB'[digit-1]+str(octave)

def main():
    d=json.loads(SRC.read_text(encoding='utf-8'));ms_per_beat=Fraction(60000,d['tempo_bpm'])
    events=[];cursor=Fraction();bars=[]
    def append(token):
        nonlocal cursor
        degree,beats=token[:2];span=Fraction(str(beats));assert span>=Fraction(1,2)
        note=degree_note(degree);tie=len(token)>2 and token[2]
        if note:
            if tie:
                assert events and events[-1]['note']==note and events[-1]['beat']+events[-1]['span']==cursor,'延音必须紧接同音'
                events[-1]['span']+=span
            else:events.append({'beat':cursor,'span':span,'note':note})
        else:assert not tie
        cursor+=span
    for token in d['pickup']:append(token)
    bar_index=0
    for name in d['order']:
        for local,bar in enumerate(d['sections'][name],1):
            assert sum(Fraction(str(t[1])) for t in bar)==4,(name,local)
            bar_index+=1;bars.append({'bar':bar_index,'section':name,'local_bar':local,'time_ms':d['lead_in_ms']+int(cursor*ms_per_beat)})
            for token in bar:append(token)
    csv=['# Qilixiang - user supplied score, simplified solo melody',
         '# BPM80;1=C4;TRANS=0;single notes;no automatic backing audio',
         '# Intro/second verse omitted;dense notes simplified;ties merged',
         'PIANO28,1']
    for e in events:
        at=d['lead_in_ms']+int(e['beat']*ms_per_beat);span=int(e['span']*ms_per_beat)
        # 八分音符留90ms松手间隙，较长音留120ms；短音<=300ms可轻点，长音需保持。
        duration=span-(90 if span<=375 else 120)
        e.update(time_ms=at,duration_ms=duration)
        csv.append(f"{at},{duration},{e['note']}")
    OUT.parent.mkdir(parents=True,exist_ok=True);OUT.write_text('\n'.join(csv)+'\n',encoding='ascii')
    result=validate(OUT);REPORT.mkdir(parents=True,exist_ok=True);DELIVERY.mkdir(parents=True,exist_ok=True)
    # 一个音符一个提示，核对相邻触发间距及每次松手间隙，避免过密窗口影响游玩。
    gap=min(b['time_ms']-a['time_ms'] for a,b in zip(events,events[1:]));assert gap>=375
    assert all(a['time_ms']+a['duration_ms']<=b['time_ms'] for a,b in zip(events,events[1:]))
    result.update(title=d['title'],bpm=d['tempo_bpm'],tonic='C4',transpose_default=0,bars=bar_index,
                  note_range=['C4','F5'],max_simultaneous_notes=1,minimum_onset_gap_ms=gap,
                  shortest_release_gap_ms=min(90 if int(e['span']*ms_per_beat)<=375 else 120 for e in events),
                  timeline_end_ms=d['lead_in_ms']+int(cursor*ms_per_beat),maximum_hold_ms=max(e['duration_ms'] for e in events),
                  source_json_sha256=sha(SRC),csv_sha256=sha(OUT),hardware_tested=False,
                  adaptation=d['description'],section_bars=bars)
    (REPORT/'chart_events.json').write_text(json.dumps({'summary':result,'events':[{k:v for k,v in e.items() if k not in ['beat','span']} for e in events]},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    # 用CSV导出的同一批时间、时长和琴键生成独立预听；这是参考音，不是FPGA音色采样。
    import numpy as np
    rate=24000;audio=np.zeros(int((result['timeline_end_ms']/1000+0.5)*rate),dtype=np.float64)
    semitones={'C':0,'D':2,'E':4,'F':5,'G':7,'A':9,'B':11}
    for e in events:
        midi=12*(int(e['note'][1])+1)+semitones[e['note'][0]];freq=440*2**((midi-69)/12)
        dur=e['duration_ms']/1000;t=np.arange(int((dur+0.08)*rate))/rate
        env=np.minimum(t/0.008,1)*np.exp(-1.2*t)*np.minimum(np.maximum((dur+0.08-t)/0.08,0),1)
        tone=(np.sin(2*np.pi*freq*t)+0.24*np.sin(4*np.pi*freq*t)+0.08*np.sin(6*np.pi*freq*t))*env
        start=round(e['time_ms']*rate/1000);end=min(len(audio),start+len(tone));audio[start:end]+=tone[:end-start]
    pcm=np.rint(audio/max(1,float(np.max(np.abs(audio))))*20000).astype('<i2')
    with wave.open(str(REPORT/'QLX_EASY_PREVIEW.wav'),'wb') as f:f.setparams((1,2,rate,len(pcm),'NONE','not compressed'));f.writeframes(pcm.tobytes())
    # 为逐关卡HDL回放生成十六进制输入文件，不改既有30项整机回归的源码。
    for name,vals in [('times',[e['time_ms'] for e in events]),('durations',[e['duration_ms'] for e in events]),('masks',[1<<((int(e['note'][1])-3)*7+'CDEFGAB'.index(e['note'][0])) for e in events])]:
        (REPORT/f'{name}.hex').write_text(''.join(f'{v:08x}\n' for v in vals),encoding='ascii')
    (REPORT/'summary.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k!='section_bars'},ensure_ascii=False,indent=2))
if __name__=='__main__':main()
