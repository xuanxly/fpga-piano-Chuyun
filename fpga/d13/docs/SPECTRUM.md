# 七键压力琴：HDMI 频谱首版

2026-10-20。用户选定微雪 5inch HDMI LCD (H)，5 寸电容屏、800×480。
首版只分析 FPGA 自己合成的琴声；32 频段绿红渐变柱状图、白色下降峰值线，下方显示七键、半音移调和明暗状态。
保留旋钮移调与明暗按钮的原功能；USB 触摸首版不实现，采用用户已经认可的固定第一模式。

## 工程入口与连接

- 用 Gowin 打开 `D:/FPGA/13_learning/pressure_piano/pressure_piano.gprj`。
- 整机顶层为 `pressure_piano_visual_top`；`pressure_piano_top` 继续负责原有声音与控制逻辑。
- PCB2/PCB3 继续按 V3 接线，不需要为显示增加任何杜邦线。
- NEO Dock HDMI → 屏幕标准 HDMI。屏幕需要另外通过其标注的 **5V 电源口**供电，可用厂家建议的 5V/2A 适配器；不从 FPGA GPIO 或 3.3V 排针给屏幕供电。
- 暂不连接屏幕 TOUCH USB 到 FPGA。屏幕有 USB 触摸功能，不等于 FPGA 已实现 USB 主机和 HID 解析。
- 声音继续从板载 PT8211/功放/扬声器输出。本版发送的是 DVI 兼容视频，未实现 HDMI 音频，因此屏幕耳机口没有本工程的音频。
- PCB 实物的断电检查尚未完整通过；软件编译不替代此前未完成的焊接、供电与线序检查。

## 音频与频谱的数据路径

```text
MCP3008 → 压力处理 → 四复音合成 → 明暗滤波 → PT8211 → 板载功放
                                      └→ PCM 双缓冲 → 去均值/加窗
                                          → 2048 点 FFT → 32 频段
                                          → 握手快照 → 像素绘制 → DVI TX → HDMI
```

频谱旁路读取 DAC 每帧捕获的有符号 16 位 PCM，不回压音频，不更改采样节拍。
系统时钟 50 MHz；音频 48 kHz。2048 点数据窗长 42.667 ms，频率间隔 23.4375 Hz，数据约每秒更新 23.4375 次。
这段窗长属于可视化延迟，不是琴键到声音的控制延迟；音频路径不等待 FFT。

每帧先去均值，再乘 Q1.15 Hamming 窗，之后做基二、时分复用的定点复数 FFT。
数据 RAM 实/虚部各十八位，每级蝶形除二，最终为 1/2048 归一化结果。系数由 `tools/spectrum_reference.py` 生成，位于 `rom/`。
FFT 实现与参考采用正常的有符号采样，不沿用原项目 FFT 前取绝对值的操作。

使用 bin 1～853（约 23.44 Hz 至 20 kHz），分成 32 个不重叠、近似对数分布的频段。
每段取 `abs(real)+abs(imag)` 的最大值，再转为八位近似对数高度；详细边界在 `reports/spectrum_reference.json`。
这是视觉幅度，不是校准后的 dB SPL 或精确 dBFS；没有照搬原麦克风项目的高频额外增益。
显示按固定视频帧平滑高度，峰值立即上升、约每 100 ms 下降三档，静音最终归零。

## 视频时序与时钟

厂家文档的 `hdmi_cvt 800 480 60 6 0 0 0` 表示 800×480、60 Hz、15:9 的 CVT 模式。
本版以此为依据，水平后肩增加8像素，使用整数 PLL 得到精确 60 Hz 的如下自定义时序。
该时序不是把厂家 CVT 配置逐项照搬；选择它是为了消除工具对分数 PLL 的频率识别差异。兼容性仍须以真实屏幕锁定与显示实测为准。

| 参数 | 水平 | 垂直 |
|---|---:|---:|
| 有效区 | 800 | 480 |
| 前肩 | 24 | 3 |
| 同步宽度 | 72 | 7 |
| 后肩 | 104 | 10 |
| 总计 | 1000 | 500 |
| 同步极性 | 负 | 正 |

像素时钟 30 MHz，实际帧率为 30 MHz/(1000×500)=60 Hz。
GW5AT-60B PLL：50 MHz × 15 = 750 MHz VCO；输出分别除 5、25，得到 150 MHz 串行时钟与 30 MHz 像素时钟。
两个 PLL 输出保持相关时钟约束，不能错误声明为彼此异步。显示数据通过 request/acknowledge 双向握手跨域，发送总线一直保持到接收确认，只在垂直消隐更新屏幕快照。
状态总线另有最大延迟约束，不能把多位状态各自同步后当成同一帧数据。

## 引脚与电压

原有 24 个 LOC 不变。新增 HDMI 沿用 Sipeed 官方 NEO Dock 约束：

| 信号 | FPGA 差分球位 |
|---|---|
| TMDS data0 | J14 / H14 |
| TMDS data1 | J15 / H15 |
| TMDS data2 | K17 / J17 |
| TMDS clock | G15 / G16 |
| HPD 辅助使能 | K13 |

这里的 J14 是 FPGA 封装球位，不是控制板连接的 J14 排针。
按照官方 Tang Mega 60K 硬件说明，工程 **VCCX 改为 1.8V**；VCCAUX=3.3V、原 GPIO Bank VCCIO 和外设 3.3V 均保留。
此操作修改的是 Gowin 的器件配置选项，不是调整开发板的物理电源。
原工程快照在 `backups/before_spectrum_20261020/`。

## 源码与验证入口

| 文件 | 职责 |
|---|---|
| `src/pressure_piano_visual_top.v` | 音频与视频的整机顶层 |
| `src/spectrum_fft.v` | PCM 缓冲、去均值、加窗、FFT、32 频段 |
| `src/spectrum_video.v` | 时序、快照握手、柱状图、峰值和点阵状态栏 |
| `src/spectrum_board.v` | DVI IP 接口与仿真替代模型 |
| `src/ip/spectrum_pll.v` | 真实 GW5AT-60B PLL 包装 |
| `src/ip/DVI_TX_Top.v` | 官方示例随附的 Gowin 加密 DVI TX IP |
| `sim/tb_spectrum_fft.sv` | 六帧数值自检与 6138 个复数频点核对 |
| `sim/tb_spectrum_video.sv` | 六帧像素时序、跨域完整性及画面输出 |
| `sim/tb_spectrum_animation.sv` | 攻速、峰值回落、静音归零 |
| `sim/tb_visual_top.sv` | 真实采样节拍下的整机音频/频谱回归 |

```powershell
& .\tools\run_tests.ps1
& .\tools\run_implementation.ps1
```

仿真宏 `PIANO_XSIM` 只替代厂商 PLL 与加密 DVI TX；RTL 数值、ADC/DAC 串行、视频几何、图像及 CDC 协议仍实际运行。
这不等于已验证真实 TMDS 编码、模拟电气、线缆或屏幕锁定。实际执行结果以 `reports/spectrum_verification_20261020.md` 为准。
预览图来自 RTL 视频仿真的合成展示数据，不是实拍频谱或真实演奏测量。

## 上屏顺序

1. 先保持两块自制 PCB 与 FPGA 脱离，完成 LCD 单独供电与 HDMI 检查；不热插拔排针。
2. 确认实现报告通过且 `device.cfg` 为 VCCX=1.8，再选择此次生成的 `.fs` 做 SRAM Program；不要使用备份中的旧位流。
3. 无外设时应看到静止界面、零频谱和未按下琴键。只有完成之前的 PCB 电气核查，才断电接回两块 PCB。
4. 再验证一键、和弦、持续压力、旋钮移调、明暗和频谱联动。把屏幕锁定、是否闪屏、声音与延迟分别记录。

## 开源来源与保留信息

原项目：`D:/Gowin/tmp/hack_spectrum_v1.0/hack_spectrum_v1.0`，作者 HACK实验室。
原实现为 ESP32/Arduino + ICS-43434 麦克风 + 32×16 WS2812B，不是可直接加入 Gowin 的 HDL。
本次参考其柱状图、峰值与绿红配色构思，重新编写 FPGA 定点 DSP 与视频链路，没有带入 ESP32、FreeRTOS、FastLED 或 arduinoFFT 源码。
原项目说明和 GPLv3 文本保留于 `third_party/hack_spectrum/`；分发时保留作者信息与相应许可证。
Gowin DVI IP 与 PLL 文件保留其原始版权头，厂商 IP 不被声明为本项目原创或任意重新许可。

官方资料：

- [微雪中文 H 版文档](https://www.waveshare.net/wiki/5inch_HDMI_LCD_(H))
- [微雪英文同型号文档](https://www.waveshare.com/wiki/5inch_HDMI_LCD_(H))：800×480、60Hz 配置、USB 触摸、5V 供电。
- [Sipeed 60K cam_dvi 说明](https://github.com/sipeed/TangMega-60K-example/blob/main/cam_dvi/readme.md)：VCCX=1.8、HDMI/DVI 示例。
- [官方 NEO Dock 约束](https://github.com/sipeed/TangMega-60K-example/blob/main/cam_dvi/src/NEO_DOCK.cst)。
