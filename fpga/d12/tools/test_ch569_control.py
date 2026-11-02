"""Execute the target USB EP0 code against named mock registers, not physical USB."""
from pathlib import Path
import re,subprocess,os
R=Path(__file__).resolve().parents[1];W=R/'reports/ch569_control_mock';W.mkdir(exist_ok=True)
source=(R/'firmware/ch569/usb_device.c').read_text(encoding='utf-8')
regs=sorted(set(re.findall(r'\bR(8|16|32)_(\w+)\b',source)))
header='#include <stdint.h>\n#include <string.h>\n#include "CH56xSFR.h"\n'
for bits,name in regs:header+=f'#undef R{bits}_{name}\nstatic volatile uint{bits}_t mock_{name};\n#define R{bits}_{name} mock_{name}\n'
(W/'CH56x_common.h').write_text(header)
gcc='D:/msys64/ucrt64/bin/gcc.exe';env=os.environ.copy();env['PATH']=str(Path(gcc).parent)+os.pathsep+env['PATH']
args=[gcc,'-O2','-Wno-pointer-to-int-cast','-I'+str(W),'-I'+str(R/'third_party/ch569/EVT/EXAM/SRC/Peripheral/inc'),'-I'+str(R/'firmware/ch569'),str(R/'sim/test_ch569_control.c'),str(R/'firmware/ch569/msc_bot.c'),'-o',str(W/'test.exe')]
subprocess.run(args,check=True,env=env);p=subprocess.run([str(W/'test.exe')],capture_output=True,text=True,env=env);print(p.stdout,p.stderr);(W/'test.log').write_text(p.stdout+p.stderr);assert p.returncode==0
