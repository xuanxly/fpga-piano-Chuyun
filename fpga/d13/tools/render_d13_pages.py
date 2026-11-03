"""Convert exact RTL P6 bytes, accepting Windows CRLF without consuming pixel data."""
from pathlib import Path
from PIL import Image
import re,json,hashlib
R=Path(__file__).resolve().parents[1];W=R/'reports/xsim_d13_final_components';rows=[]
for page in [0,8,9]:
 p=W/f'd13_page{page}.ppm';raw=p.read_bytes()
 m=re.match(rb'P6\r?\n(\d+) (\d+)\r?\n255\r?\n',raw);assert m,p
 width,height=map(int,m.groups());assert (width,height)==(800,480)
 pixels=raw[m.end():];assert len(pixels)==width*height*3
 png=p.with_suffix('.png');Image.frombytes('RGB',(width,height),pixels).save(png)
 rows.append({'page':page,'size':[width,height],'pixel_sha256':hashlib.sha256(pixels).hexdigest(),'png_sha256':hashlib.sha256(png.read_bytes()).hexdigest()})
(R/'reports/d13_ui_images.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
print('PASS three exact RTL RGB images converted without CRLF pixel shift')
