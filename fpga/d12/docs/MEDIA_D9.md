# D9 媒体功能与验证边界

本工程基于 D8，保留 28 个实体压力键、触屏键盘、双滑柱、3.5mm 耳机输出、USB 手动启动保护和灯光。原 D8 目录及位流不改动。

## 功能

Home 有 Spectrum、Keyboard、Recorder、Files 四个入口。Home 仍可调节音量和移调，实体键仍发声。

Recorder 基于 28 键布局。RECORD/END RECORDING 开始、结束；PAUSE/CONTINUE 暂停、继续。暂停区间不写入文件，回 Home 继续录音。录音取滤波后、主音量前的内部 PCM，因此保留力度、移调、明暗效果，主音量为 0 仍能录到琴声。

录音规格：48kHz、16bit、单声道 PCM WAV，最多 300 秒有效声音，即 14,400,000 个采样。达到上限自动结束。根目录自动命名 REC0001.WAV 起，使用 CREATE_NEW 避免覆盖旧文件。提前尝试连续预分配约 28.8MB，结束时回写 WAV 头并截断到实际长度。

Files 每页显示六项，支持进入文件夹、UP、PREV、NEXT、REFRESH。后台保留 Unicode 路径，画面显示英文大写，不能显示的字符显示问号。建议文件使用英文名称。目录不限制为六个文件；上一首/下一首会跨越分页并跳过目录及不支持的文件。

支持读取 FAT32、exFAT，不自动格式化。128GB SDXC 使用 SPI 块寻址。实际卡的分区表、文件系统和电气兼容性仍需上板确认；主机模拟使用虚拟卡。

播放支持 16bit PCM WAV（单/双声道，8kHz～48kHz）和 MPEG Layer III MP3（CBR/VBR，8kHz～48kHz）。48kHz WAV 不重采样；其他采样率用定点线性插值到 48kHz。输出保留左右声道。

播放页有暂停/继续、STOP、进度拖动、上一首/下一首、时间和返回 Files。拖动松手后才跳转，避免连续重读卡。音量可调，移调柱置灰。播放和播放暂停期间屏蔽琴音；离开播放页立即撤销文件音频独占并关闭文件，不后台播放。录音尚未结束时打开音频提示 END RECORD FIRST。

播放循环在每个已解码音频块的边界检查触摸命令，避免每个48kHz采样都读取外设事件寄存器；解码与重采样算术未改变。Home/返回的硬件页面门控立即撤销文件音频独占，文件关闭随后由软件完成。

## 边界

- WAV 播放不支持压缩 WAV、24/32bit WAV、浮点 WAV；文件大于 4GiB 会拒绝播放。
- MP3 的 free-format、损坏帧和额外封装不保证支持。有 Xing/Info 帧数时用其计算时长；有 TOC 时使用其跳转，否则时长和进度按首帧码率估计，VBR 跳转可能不精确。
- 当前单卷、单流、最大路径 255 个 UTF16 单元；不提供删除、重命名、格式化、后台播放和断电恢复。
- STOP 或播放结束后，回 Files 重新选择文件可再次播放。目录按卡内条目顺序显示，文件时间使用固定 FAT 时间，不提供实时时钟排序。
- SD 卡写入若超过缓冲承受范围，明确报告 REC OVERFLOW 并停止，不静默跳采样。录音缓冲约 256ms，播放缓冲约 128ms；实际卡的极端写入停顿仍需实测。
- 必须 END RECORDING 并看到 RECORD SAVED 后，再断电或拔卡。录制中断电可能留下未最终定长的 WAV。
- 数字仿真和静态时序通过，不等于真实 TF 卡、耳机和 USB 触摸的整机实测通过。

## 实现

50MHz RV32IM VexRiscv 软处理器运行 FatFs 与 Helix，未改 BL616/CH569 固件。指令、数据缓存各 16KB，缓存行 32 字节；对应索引、标签和清空计数同时扩大，已用实际机器码解码结果核对。

触控UI采用两级流水：第一级并行译码五个触点，第二级合并触点归属、页面和事件。相比原规则增加一个50MHz周期（20ns），切断原来的页面到五重优先链长路径。10万组随机五指报告与原始规则对照，另测CPU导航中断在途报告，防止旧页面结果弹回。

最后的时序优化还将触点ID相等关系放到第一级寄存器，并让FIFO空/满标志与计数同拍更新。120000拍随机总线/采样/控制组合与优化前SoC逐拍比较，ACK、数据、录放音、FIFO状态、并发仲裁和SPI均一致；当前触控再做100001组报告对照。完整17项整机回归与这些最后修改的对照证据分别保留，不把旧回归日志当作重新执行过的最终源码。

最终时序约束为四种实际时钟统一增加0.300ns建立不确定度，作为额外设计保护预算；频率仍为50/30/60/150MHz。发布同时要求扣除预算后的建立/保持零违例且余量为正。该预算是设计裕量，不是振荡器抖动的实测值；原有CDC首级例外保持，普通逻辑路径继续分析。依据本机SUG940-2.0E第5.2.4节。

固件 ROM 76KB，工作 RAM 48KB（BSS/heap 约 40KB，余量给栈），录放共享环形缓冲 24KiB。录放互斥。256字节文本采用双银行RAM；CPU仅写不可见银行，帧边界提交，消费确认回来前整包拒绝新的文本发布，避免半包更新。原2211位接口的文本位变为常量，实际只传状态及银行指针。ROM 的8KiB放LUT，68KiB放BSRAM。共享音频缓冲调整为24KiB，以保留原有解码速度、减少布线拥挤；这不改变五分钟录音上限，实际卡长停顿仍按明确溢出错误处理。音频 RAM 采用单口时间仲裁；48kHz 采样只占约每 1042 个系统周期中的一拍，CPU 冲突请求延后一拍，不丢数据。奇数采样暂停尾字携带独立有效位，避免恢复后插入零采样。

新增文件：

| 路径 | 用途 |
|---|---|
| src/media_soc.v | 处理器总线、事件、音频缓冲、SD SPI、原子 UI 状态 |
| src/media_memories.v | 物理 RAM 分银行、单口仲裁所用存储 |
| src/media_ui28.v | 六页触摸区域和多指归属 |
| src/media_ui_renderer.v | Home、录音、文件、播放画面 |
| src/VexRiscv.v | 从原始内核可复现适配的 CPU |
| firmware/media_service.c | 录音、目录、WAV/MP3、播放和跳转状态机 |
| firmware/sd_spi.c | SDXC 初始化、读写、多块传输、CRC 和超时 |
| firmware/media_hw.h | C/RTL 寄存器 ABI |
| rom/media_firmware.hex.b00 等 | 已编译的分银行固件初始化数据 |

SD SPI 的 CRC7 命令、CRC16 数据、低速初始化和 12.5MHz 运行速率都有独立协议模型检查。所有等待有界。硬件存在接触、供电、卡速差异时仍可能报错，须看屏幕状态。

## 接口

继续使用板上 TF 卡座，不外接 SD 模块。保持已确认的蓝色 SW2 六位均 ON，特别是 5/6 为 ON，维持板载下载器的 JTAG/EVB 状态。不要在运行中切到下载器 SPI 模式。

| 信号 | FPGA 球位 | 电平 |
|---|---|---|
| sd_cs_n | W15 | LVCMOS33 |
| sd_sck | V15 | LVCMOS33 |
| sd_mosi | Y16 | LVCMOS33 |
| sd_miso | AA15 | LVCMOS33 |

原 D8 的 41 个球位保持不变。新增四个与它们不重合。音频仍从 NEO Dock 的 3.5mm 耳机口输出。

## 复现与测试

在本目录用 PowerShell 执行。不会烧录 FPGA、改 MCU 固件或格式化实体卡。

```powershell
& 'C:\Users\KUKI\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools\prepare_media_cpu.py
& 'C:\Users\KUKI\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools\build_media_firmware.py
.\tools\run_tests.ps1 -Optimize
.\tools\run_tests.ps1 -WorkSubdir media_xsim -Optimize -Benches tb_media_fifo,tb_media_ui,tb_media_audio,tb_media_video,tb_media_spi,tb_media_boot,tb_media_mp3_cpu
& 'C:\Users\KUKI\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tools\test_media_host.py
.\tools\run_vendor_pad_test.ps1
.\tools\run_implementation.ps1
```

重建 C 固件需要 tools/compiler_path.json 所指的独立 RISC-V 编译器。直接在 Gowin 打开现有工程，不需要安装 C 编译器，ROM 已包含固件。仿真 MP3 基准前运行 tools/build_media_benchmark.py 生成参考数据。主机文件系统测试把可格式化选项只开在 reports/host_media 的副本中，产品 FatFs 不含格式化功能。

第三方代码、原始归档 SHA、CPU 上游版本、许可证保留在 third_party。Helix 带 RPSL/RCSL 许可证及本地优化改动；VexRiscv 保留 MIT 许可证；FatFs 保留原许可声明。重建默认使用已存源码，不应把重新下载 master 分支当作相同版本。

## 验证证据

- reports/media_host_driver.log：实际 FatFs/Helix 的 exFAT、FAT32 虚拟 128GB 集成测试，每种格式超过 1400 万项检查，含完整五分钟录音数据逐样本核对。
- reports/media_audio_quality.log：CBR、VBR、噪声MP3与独立FFmpeg解码对齐后，测试样本最大误差1个PCM量化单位，SNR超过81dB。
- reports/media_sd_protocol.log：独立 SDXC 字节协议模型检查真实 sd_spi.c，68 项检查。
- reports/media_pipeline_cpu.log：真实CPU运行实际播放调度、20帧MP3解码、44.1k→48k插值和立体声FIFO，以实际48kHz消费25078个采样，零欠载。此测试使用内存提供f_read，SD读写另用位级模型测量，真实卡的忙等待尚未覆盖。
- reports/media_sd_pipeline_cpu.log：实际CPU、生产sd_spi.c、SPI硬件与带14ns输入延迟/CRC的独立卡模型，连续200帧320kbps MP3、44.1k→48k重采样和实时立体声FIFO联动；消费250776个采样，无欠载，稳态缓冲最低4995字。此测试将文件字节流映射到模型扇区，未包含实体卡忙等待；FatFs目录/录音另由真实FatFs虚拟128GB集成检查。
- reports/media_sd_cpu.log：真实CPU、生产sd_spi.c、SPI硬件和独立位级SDXC模型联动，2KB多块写/读耗时245155/243846个50MHz周期，即约4.90/4.88ms；CRC与回读数据一致。此模型不代表真实卡的写入忙时延。
- reports/media_sd_pin_delay.log：独立位级卡模型改为下降沿推出数据并加入14ns输入传播延迟后，同样的真实CPU读写/CRC检查仍通过。此固定延迟不是对本机实体卡电气指标的实测。
- reports/media_stereo_stress_cpu.log：左右独立噪声的320kbps立体声MP3，三帧最大999275周期，解码输出与独立主机参考位一致。
- reports/media_benchmark_final.log：真实 VexRiscv 机器码解码三个 320kbps/44.1kHz 立体声噪声帧，PCM 与主机定点参考逐帧校验一致；最大 986431 周期，单帧实时预算 1306122 周期；这项结果只测解码，连续播放另测调度、重采样和FIFO。计数取总线标记之间的实际时钟，早期 CSR 读零日志已作废。
- reports/media_rtl_final.log、reports/media_text_bank.log：六页、录音音量旁路、立体声 DAC、暂停尾样本、非 2 次幂缓冲绕回、并发访问仲裁、溢出、五分钟计数边界等。
- reports/regression_d9.log：43 项原有回归；存储优化后的USB/音频/顶层集成复查记录在 reports/media_final_integration.log。
- reports/vendor_pad_d9.log：原生厂商 IOBUF、配置后无时钟高阻 INIT、异常释放保护。
- reports/ui_equivalence.log：100001组报告与原单拍规则比较，覆盖五指ID换序、归属、音量/音调/进度、动作优先级及六页；另检查CPU导航打断在途译码。
- reports/bank_local_tests.log、reports/bank_local_cpu_tests.log：最终 ROM 读口的全部 19456 个固件字、随机地址及停读保持检查；再运行真实 CPU 启动、MP3 定点解码和 SD 多块读写。8KB LUT ROM 按银行锁存地址，剩余 68KB 使用 BSRAM，降低全局地址线扇出。
- reports/media_native_rom.log：独立 ROM 模块实际布局布线的 `.vo` 网表与高云原生仿真库联动，21504 次访问通过，确认 76KB 固件字及物理 ROM/LUT 初始化一致。该探针没有开发板约束或有效系统时序检查，其位流禁止用于上板。
- reports/media_native_ram.log：工作RAM与音频RAM的独立实际布线网表/原生库，26624次访问通过，覆盖48KB工作RAM、字节掩码和24KiB单口音频RAM的34位数据（含尾样本有效数量）。同样仅为功能探针，禁止使用探针位流上板。
- reports/ui_previews：真实 RTL 渲染的六页画面。
- reports/implementation_driver.json：最终新位流、构建输入一致、Setup/Hold 零违例检查；只有此文件最终通过，才可视为实现通过。

整机真实 SD 卡的录音、长时间 MP3 播放、实际触摸和模拟音质需要上板完成，不包含在上述数字结论中。
