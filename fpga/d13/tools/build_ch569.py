"""Build only. Never opens USB, invokes a programmer, or writes hardware flash."""
from pathlib import Path
import subprocess,json,hashlib,re
R=Path(__file__).resolve().parents[1];W=R/'reports/ch569_build';W.mkdir(exist_ok=True)
gcc=Path(json.loads((R/'tools/compiler_path.json').read_text())['gcc']);prefix=str(gcc).removesuffix('gcc.exe')
src=R/'third_party/ch569/EVT/EXAM/SRC'
files=[R/'firmware/ch569/start.S',R/'firmware/ch569/main.c',R/'firmware/ch569/link.c',R/'firmware/ch569/msc_bot.c',R/'firmware/ch569/usb_device.c',R/'firmware/minilib.c',src/'Peripheral/src/CH56x_clk.c']
inc=[R/'firmware/ch569',src/'Peripheral/inc',src/'RVMSIS']
elf=W/'piano_d12_ch569.elf'
args=[str(gcc),'-march=rv32imac_zicsr','-mabi=ilp32','-Os','-flto','-ffreestanding','-fno-builtin','-fno-tree-loop-distribute-patterns','-ffunction-sections','-fdata-sections','-nostdlib','-msmall-data-limit=0']
args+=['-I'+str(p) for p in inc]+[str(p) for p in files]+['-T'+str(R/'firmware/ch569/link.ld'),'-Wl,--gc-sections','-Wl,-Map='+str(W/'piano_d12_ch569.map'),'-o',str(elf),'-lgcc']
p=subprocess.run(args,capture_output=True,text=True);(W/'compile.log').write_text(p.stdout+p.stderr,encoding='utf-8');assert p.returncode==0,p.stderr
for fmt,ext in [('binary','bin'),('ihex','hex')]:subprocess.run([prefix+'objcopy.exe','-O',fmt,str(elf),str(W/('piano_d12_ch569.'+ext))],check=True)
size=subprocess.check_output([prefix+'size.exe',str(elf)],text=True);print(size)
# 一并固定头文件和构建入口，防止只改协议/寄存器头文件后误用旧HEX。
inputs=files+[R/'firmware/ch569/link.ld',Path(__file__).resolve()]
for directory in inc:inputs+=list(directory.rglob('*.h'))
manifest={'state':'BUILT_NOT_FLASHED','compiler':str(gcc),'size':size,'sources':{str(p.relative_to(R)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(set(inputs))},'binary_sha256':hashlib.sha256((W/'piano_d12_ch569.bin').read_bytes()).hexdigest()}
(W/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('CH569 compiled; no hardware operations performed')
