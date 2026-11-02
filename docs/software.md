# D12 软件功能与实拍

[返回项目首页](../README.md) · [工程入口](../fpga/README.md) · [完整技术文档](technical-report.docx)

HDL承担实时压力处理、触摸解析、28声部五音色合成、FFT、画面、灯光及音游判定；VexRiscv软核负责FatFs、WAV录放、CSV装载和USB扇区服务。

|功能|D12实现|
|---|---|
|演奏|四行七列28键、最多五触点，同键力度合并，共用28声部|
|声音|五种音色，48 kHz / 16位PCM，±5半音、明暗或揉弦|
|录放|最长5分钟单声道PCM WAV录音；16位PCM WAV回放|
|视觉|2048点FFT、32频段、800×480画面、112灯空间波纹|
|音游|CSV谱面，练习与挑战，和弦、长音及灯光引导|
|传输|CH569 USB MSC磁盘，SD卡与电脑双向文件复制|

照片记录原型界面；数值范围来自D12代码，数字验证与专项实测分别列在技术文档中。

## HOME六个应用入口

![HOME六个应用入口](../assets/photos/software/home.png)

## 录音页、RECORD/PAUSE与4×7触屏键盘

![录音页、RECORD/PAUSE与4×7触屏键盘](../assets/photos/software/recorder.png)

## 钢琴、电钢琴、风琴、吉他、弦乐五音色

![钢琴、电钢琴、风琴、吉他、弦乐五音色](../assets/photos/software/timbre.jpg)

## 触摸演奏与32频段可视化

![触摸演奏与32频段可视化](../assets/photos/software/spectrum.png)

## TF卡目录及REC录音保存文件夹

![TF卡目录及REC录音保存文件夹](../assets/photos/software/files.png)

## CSV选曲、挑战模式与28键区域

![CSV选曲、挑战模式与28键区域](../assets/photos/software/game.jpg)
