"""Create editable, original short exercises rather than pre-recorded music."""
from pathlib import Path
R=Path(__file__).resolve().parents[1];out=R/'tf_card/SONGS';out.mkdir(parents=True,exist_ok=True)
songs={
 'SCALE.CSV':[(i*500,250,n) for i,n in enumerate(['C3','D3','E3','F3','G3','A3','B3','C4','B3','A3','G3','F3','E3','D3','C3'])],
 'CHORDS.CSV':[(0,1000,'C3+E3+G3'),(1500,1000,'F3+A3+C4'),(3000,1000,'G3+B3+D4'),(4500,1500,'C3+E3+G3+C4')],
 'FOUR_ROWS.CSV':[(i*600,300,n) for i,n in enumerate(['C3','E3','G3','C4','E4','G4','C5','E5','G5','C6','E6','G6','B6','G6','E6','C6'])],
 'HOLD_TEST.CSV':[(0,3000,'C3'),(500,1000,'E3'),(1000,800,'G3'),(2000,800,'C4'),(3500,500,'C3+E3+G3+C4')],
 'RHYTHM.CSV':[(i*250,120,['C4','E4','G4','E4'][i%4]) for i in range(32)],
 'ALL_KEYS.CSV':[(0,2000,'+'.join(n+str(o) for o in range(3,7) for n in 'CDEFGAB'))],
 'NEXT_PAGE.CSV':[(0,300,'C3'),(600,300,'B6')],
}
for name,events in songs.items():
 (out/name).write_text('# D12 original practice exercise; time_ms,duration_ms,notes\nPIANO28,1\n'+''.join(f'{at},{duration},{notes}\n' for at,duration,notes in events),encoding='ascii')
(R/'tf_card/README.txt').write_text('Copy SONGS folder to the root of a single-partition FAT32 or exFAT TF card.\nDo not copy MP3 expecting playback: D12 WAV only.\nCSV: PIANO28,1 then time_ms,duration_ms,C3+E3+G3. English file names.\nTimes strictly increase; simultaneous notes share one line.\nUse C,D,E,F,G,A,B and octaves3..6. Maximum300000ms/4096events.\nFinish copying, eject/disconnect the phone, then tap EJECT DISK on the FPGA.\n',encoding='ascii')
print('Prepared',len(songs),'original CSV exercises')
