"""Independent sample-domain model, not an HDL implementation mirror by clock/state."""
from pathlib import Path
import math,json
R=Path(__file__).resolve().parents[1];W=R/'reports/xsim_d13_final_components'
def sat(v):return max(-32768,min(32767,v))
def decay(v,bits):return -(abs(v)>>bits) if v<0 else v>>bits
echo=[0]*6144;comb=[[0]*n for n in [1499,1601,1747,1867]];ap=[0]*223;chorus=[0]*2048
e=0;cp=[0]*4;a=0;c=0;phase=0;max_value=0;tails=[0]*8;clipped=0;gains=[0]*3
lines=(W/'effects28_samples.csv').read_text().splitlines()
for n,line in enumerate(lines):
 en,dry,rg,eg,cg,actual,clip=map(int,line.split(','))
 for k,target in enumerate([rg if en&1 else 0,eg if en&2 else 0,cg if en&4 else 0]):gains[k]+=int(gains[k]<target)-int(gains[k]>target)
 triangle=(phase>>14)&0x1ffff
 if phase&0x80000000:triangle^=0x1ffff
 delay=(512<<16)+(triangle<<9);base=(c-(delay>>16))%2048;frac=(delay>>8)&255
 cq0,cq1=chorus[base],chorus[(base-1)%2048]
 wet_ch=sat(cq0+(((cq1-cq0)*frac)>>8))
 old=[comb[k][cp[k]] for k in range(4)]
 av=sum(v>>2 for v in old);aw=sat(av+decay(ap[a],1));wet_r=sat(ap[a]-(aw>>1));wet_e=echo[e]
 mixed=dry+((wet_r*gains[0])>>8)+((wet_e*gains[1])>>7)+((wet_ch*gains[2])>>8)
 expected=sat(mixed)
 assert actual==expected,(n,en,dry,actual,expected,old,wet_ch,wet_r)
 assert clip==int(mixed>32767 or mixed< -32768),(n,'clip flag')
 clipped+=clip;max_value=max(max_value,abs(actual))
 if dry==0 and actual:tails[en]+=1
 echo[e]=sat(decay(dry,1)+decay(wet_e,1));e=(e+1)%6144
 for k in range(4):comb[k][cp[k]]=sat(decay(dry,2)+decay(old[k]*3,2));cp[k]=(cp[k]+1)%len(comb[k])
 ap[a]=aw;a=(a+1)%223;chorus[c]=dry;c=(c+1)%2048;phase=(phase+71583)&0xffffffff
assert len(lines)==91300
assert all(tails[k]>0 for k in [1,2,4,7]),tails
pcm=list(map(int,(W/'validation32_pcm.txt').read_text().splitlines()))
# 375Hz间隔正好为FFT bin 16；舍弃起始帧，直接DFT验证全部32路主频贡献。
data=pcm[-2048:];bins=[]
for k in range(1,33):
 re=sum(v*math.cos(2*math.pi*k*16*i/2048) for i,v in enumerate(data))
 im=sum(v*math.sin(2*math.pi*k*16*i/2048) for i,v in enumerate(data))
 amplitude=2*math.hypot(re,im)/2048;assert amplitude>450,(k,amplitude)
 bins.append({'Hz':375*k,'FFT_bin':16*k,'amplitude':amplitude})
out={'effect_samples_exact':len(lines),'nonzero_tail_samples':tails,'peak':max_value,'saturations':clipped,
     'test_tone_PCM_samples':len(pcm),'independently_observed_tones':bins,'boundary':'RTL/model verification, not hardware or analog measurement'}
(R/'reports/d13_audio_reference.json').write_text(json.dumps(out,indent=2),encoding='utf-8')
print('PASS independent FX model:',len(lines),'exact samples; 32 DFT peaks at375..12000Hz')
