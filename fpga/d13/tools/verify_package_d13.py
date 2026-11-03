"""Read-only verification of this folder, independent of the old project path."""
from pathlib import Path
import hashlib,json,xml.etree.ElementTree as ET,re,sys
R=Path(__file__).resolve().parents[1]
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  while b:=f.read(1024*1024):h.update(b)
 return h.hexdigest().upper()
m=json.loads((R/'PACKAGE_MANIFEST.json').read_text(encoding='utf-8'))
for rel,info in m['files'].items():
 p=R/rel;assert p.is_file(),('missing',rel);assert sha(p)==info['sha256'],('modified',rel)
refs=[]
for e in ET.parse(R/'pressure_piano_touch.gprj').iter('File'):
 p=R/e.attrib['path'].replace('\\','/');assert p.resolve().is_relative_to(R.resolve()) and p.is_file(),p;refs.append(p)
assert len(refs)==58
v=json.loads((R/'reports/d13_verification.json').read_text(encoding='utf-8'))
for rel,h in v['source_hashes'].items():assert sha(R/rel)==h,('D13 source mismatch',rel)
for name,t in v['tests'].items():
 p=R/t['log'].replace('\\','/');assert sha(p)==t['sha256'],('historical test log mismatch',name)
assert v['test_count']==34
assert sha(R/'impl/pnr/pressure_piano_touch.fs')==m['fpga_sha256']
assert sha(R/'firmware/release/piano_d12_ch569.hex')==m['ch569_hex_sha256']
with (R/'impl/pnr/pressure_piano_touch.fs').open(encoding='utf-8-sig') as f:head=''.join(next(f) for _ in range(15))
assert 'usercode: 0x0000c02f' in head.lower(),head
print('PASS package manifest:',len(m['files']),'files;58 project references;34 historical logs;C02F FPGA and CH569 HEX;no hardware operations')
