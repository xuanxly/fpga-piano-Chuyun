"""Check that the added constraints target only direct copies of held-bus destination registers."""
from pathlib import Path
import re,json
R=Path(__file__).resolve().parents[1]
def check():
 s=(R/'impl/pnr/pressure_piano_touch.vo').read_text(encoding='utf-8-sig')
 c=(R/'constraints/pressure_piano_touch.sdc').read_text(encoding='utf-8-sig')
 cells={}
 for t,n,b in re.findall(r'^(DFF\w*)\s+(\\[^\s]+|\w+)\s*\((.*?)^\);',s,re.M|re.S):
  cells[n.lstrip('\\')]=(t,{k:re.sub(r'\s+','',v) for k,v in re.findall(r'\.(\w+)\((.*?)\)',b,re.S)})
 scopes={'u_touch_cdc':('gowin_replicate_reg_touch_',16.667),'u_system/u_media_snapshot':('gowin_replicate_reg_pixel_media',30)}
 results={}
 for scope,(alias,limit) in scopes.items():
  prefix=scope+'/'
  original={n:p for n,(t,p) in cells.items() if n.startswith(prefix+'dst_') and p.get('D','').startswith('\\'+prefix+'held_data[')}
  assert original,(scope,'no original held-bus destinations')
  replicas={n:p for n,(t,p) in cells.items() if n.startswith(prefix+alias)}
  for n,p in replicas.items():
   assert p.get('D','').startswith('\\'+prefix+'held_data['),(n,'not direct held data')
   matching=[q for q in original.values() if q.get('D')==p.get('D') and q.get('CLK')==p.get('CLK') and q.get('CE')==p.get('CE')]
   assert matching,(n,'copy does not share original data, clock and handshake CE')
   source=[q for _,q in cells.values() if q.get('Q')==p['D']]
   assert len(source)==1 and source[0]['CLK']!=p['CLK'],(n,'source clock is not the expected other domain')
  for pattern in ['dst_*' if scope=='u_touch_cdc' else 'dst_data*',alias+'*']:
   assert f'set_max_delay {limit} -from [get_regs {{{scope}/held_data*}}] -to [get_regs {{{scope}/{pattern}}}]' in c
   assert f'set_false_path -hold -from [get_regs {{{scope}/held_data*}}] -to [get_regs {{{scope}/{pattern}}}]' in c
  results[scope]={'direct_original_registers':len(original),'replicas_checked':len(replicas),'max_delay_ns':limit,'same_data_clock_handshake_CE':True,'replica_names':list(replicas)}
 (R/'reports/d13_cdc_physical_coverage.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
 print('PASS direct held-bus replica constraint coverage:',{k:v['replicas_checked'] for k,v in results.items()})
 return results
if __name__=='__main__':check()
