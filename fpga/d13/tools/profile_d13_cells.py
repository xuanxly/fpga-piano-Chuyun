"""Read-only hierarchy profile of the actual post-mapping Verilog primitives."""
from pathlib import Path
from collections import defaultdict,Counter
import re,json,argparse
R=Path(__file__).resolve().parents[1]
args=argparse.ArgumentParser()
args.add_argument('--input',type=Path,default=R/'impl/pnr/pressure_piano_touch.vo')
args.add_argument('--output',type=Path,default=R/'reports/d13_cell_profile.json')
a=args.parse_args()
s=a.input.read_text(encoding='utf-8-sig')
prefixes=defaultdict(Counter)
for t,n in re.findall(r'^(\w+)\s+(\\[^\s]+|\w+)\s*\(',s,re.M):
 if t in ['module','function']:continue
 kind='logic' if t.startswith(('LUT','ALU','ROM16','RAM16')) else 'FF' if t.startswith('DFF') else 'BSRAM' if t in ['SP','SPX9','DP','DPX9','SDPB','SDPX9B','pROM','pROMX9'] else t
 p=n.lstrip('\\').split('/')
 for depth in range(1,min(6,len(p))):prefixes['/'.join(p[:depth])][kind]+=1
out={k:dict(v) for k,v in sorted(prefixes.items(),key=lambda p:p[1]['logic'],reverse=True)}
a.output.write_text(json.dumps(out,indent=2),encoding='utf-8')
for k,v in out.items():
 if k.count('/') in [1,2] and v.get('logic',0)>100:print(k,dict(v))
