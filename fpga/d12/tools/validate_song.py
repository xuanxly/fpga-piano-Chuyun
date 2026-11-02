"""Validate editable CSV charts with the same limits as the FPGA file service."""
from pathlib import Path
import sys,re
def validate(path):
 data=path.read_bytes();assert len(data)<=262144,'file exceeds256KiB'
 text=data.decode('ascii');header=False;last=-1;held={};end=0;count=0
 for line_no,line in enumerate(text.splitlines(),1):
  try:
   line=line.strip(' \t\r');
   if not line or line.startswith('#'):continue
   assert len(line)<128,'line too long'
   if not header:assert line=='PIANO28,1','expected PIANO28,1';header=True;continue
   line=line.partition('#')[0].rstrip();parts=line.split(',');assert len(parts)==3,'three CSV columns required'
   assert re.fullmatch(r'\s*\d+\s*',parts[0]) and re.fullmatch(r'\s*\d+\s*',parts[1]),'integer milliseconds required'
   at,duration=map(int,parts[:2]);assert at>last and 40<=duration<=60000 and at+duration<=300000,'time/duration out of range or not increasing'
   notes=[n.strip() for n in parts[2].split('+')];assert len(set(notes))==len(notes),'duplicate note'
   for n in notes:assert re.fullmatch('[CDEFGAB][3-6]',n),'use natural notes C3..B6';assert at>=held.get(n,0),'overlapping note '+n
   for n in notes:held[n]=at+duration
   last=at;end=max(end,at+duration);count+=1;assert count<=4096,'too many events'
  except (AssertionError,ValueError) as e:raise ValueError(f'{path.name}:{line_no}: {e}') from e
 assert header and count,'missing header or no notes'
 return {'file':path.name,'events':count,'duration_ms':end}
if __name__=='__main__':
 paths=list(map(Path,sys.argv[1:])) or sorted((Path(__file__).resolve().parents[1]/'tf_card/SONGS').glob('*.CSV'))
 for p in paths:print('PASS',validate(p))
