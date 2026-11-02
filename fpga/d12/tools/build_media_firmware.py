"""Cross-compile the actual RV32 firmware and embed its little-endian words in the FPGA ROM."""
from pathlib import Path
import subprocess,json,hashlib,sys
R=Path(__file__).resolve().parents[1]
gcc=Path(json.loads((R/'tools/compiler_path.json').read_text())['gcc'])
prefix=str(gcc).removesuffix('gcc.exe')
verify='--verify' in sys.argv
work=R/('reports/firmware_verify' if verify else 'reports/firmware_build');work.mkdir(exist_ok=True)
sources=[R/'firmware/start.S',R/'firmware/main.c',R/'firmware/minilib.c',R/'firmware/sd_spi.c',R/'firmware/media_service.c',R/'firmware/game_chart.c',
         R/'third_party/fatfs/ff.c',R/'third_party/fatfs/ffunicode.c']
includes=[R/'firmware',R/'third_party/fatfs',R/'third_party/helix/pub',R/'third_party/helix/real']
args=[str(gcc),'-march=rv32im_zicsr','-mabi=ilp32','-Os','-flto','-ffreestanding','-fno-builtin','-fno-tree-loop-distribute-patterns',
      '-fno-strict-aliasing','-fwrapv','-DNDEBUG','-ffunction-sections','-fdata-sections','-nostdlib','-msmall-data-limit=0']
args+=['-I'+str(p) for p in includes]+[str(p) for p in sources]
elf=work/'media.elf'
args+=['-T'+str(R/'firmware/link.ld'),'-Wl,--gc-sections','-Wl,-Map='+str(work/'media.map'),'-o',str(elf),'-lgcc']
with (work/'compile.log').open('w',encoding='utf-8') as log:
 p=subprocess.run(args,stdout=log,stderr=subprocess.STDOUT)
if p.returncode:raise SystemExit((work/'compile.log').read_text(errors='replace'))
subprocess.run([prefix+'objcopy.exe','-O','binary',str(elf),str(work/'media.bin')],check=True)
size=subprocess.check_output([prefix+'size.exe',str(elf)],text=True)
data=(work/'media.bin').read_bytes();assert len(data)<=40960
data=data.ljust(40960,b'\0')
hex_text=''.join(f'{int.from_bytes(data[i:i+4],"little"):08x}\n' for i in range(0,len(data),4))
if verify:assert (R/'rom/media_firmware.hex').read_text()==hex_text,'ROM does not match current C sources'
else:(R/'rom/media_firmware.hex').write_text(hex_text)
headers=sorted({p for folder in ['firmware','third_party/fatfs','third_party/helix'] for p in (R/folder).rglob('*.h')})
manifest={'gcc':str(gcc),'size':size,'rom_bytes':len((work/'media.bin').read_bytes()),'sha256':hashlib.sha256(data).hexdigest(),
          'inputs':{str(p.relative_to(R)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources+[R/'firmware/link.ld']+headers+sorted((R/'firmware').glob('*.inc'))}}
(work/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(size);print('Firmware ROM bytes',manifest['rom_bytes'],'SHA256',manifest['sha256'])

# Each 512-word ROM bank maps to one physical BSRAM.
bank_path=R/'rom/media_firmware.hex'
bank_lines=bank_path.read_text().splitlines()
for b in range(len(bank_lines)//512):
 p=Path(str(bank_path)+f'.b{b:02d}');expected='\n'.join(bank_lines[b*512:b*512+512])+'\n'
 if verify:assert p.read_text()==expected,('ROM bank mismatch',b)
 else:p.write_text(expected)
if verify:print('PASS current C/headers/inc -> compiled ROM and all20 banks reproduce exactly; product files untouched')
