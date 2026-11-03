# D13 软件功能与实拍

[返回项目首页](../README.md) · [工程入口](../fpga/README.md) · [完整技术文档](technical-report.docx)

HDL承担实时压力处理、触摸解析、28声部五音色合成、FFT、画面、灯光及音游判定；VexRiscv软核负责FatFs、WAV录放、CSV装载和USB扇区服务。

|功能|D13实现|
|---|---|
|演奏|四行七列28键、最多五触点，同键力度合并，共用28声部|
|声音|五种音色，48 kHz / 16位PCM，±5半音、明暗或揉弦|
|效果器|混响、回声、合唱独立开关及 0～100% 强度，作用于实时琴声与录音|
|验证与音频扩展|VERIFY 数字监测及独立 32 路测试音；J13 标准 I²S|
|录放|最长5分钟单声道PCM WAV录音；16位PCM WAV回放|
|视觉|2048点FFT、32频段、800×480画面、112灯空间波纹|
|音游|CSV谱面，练习与挑战，和弦、长音及灯光引导|
|传输|CH569 USB MSC磁盘，SD卡与电脑双向文件复制|

HOME、VERIFY 与 EFFECTS 使用最新 D13 实拍，其余照片记录延续功能。参数来自 D13 代码，数字验证与专项实测分别列在技术文档中。

## HOME八个应用入口

![HOME八个应用入口](../assets/photos/software/home.png)

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

## VERIFY 数字状态监测

![VERIFY 数字状态监测](../assets/photos/software/verify.jpg)

可主动启用 1/4/8/16/28/32 路测试音，观察采样计数、正常乐器引擎 LAST/MAX 周期、数字门控至 DAC 帧计数及峰值/故障状态。照片中的 `0896` 为正常 28 声部引擎周期；32 路测试引擎独立运行。`GATE→DAC` 是数字测点，模拟端到端延迟需另行测量。

## EFFECTS 三种硬件效果

![EFFECTS 混响回声合唱](../assets/photos/software/effects.jpg)

三种效果可同时打开，照片显示强度为 40%、35%、35%。页面切换保留本次运行的参数；录音捕获效果输出，监听音量不影响录音文件幅度。文件播放器沿独立通道回放。
