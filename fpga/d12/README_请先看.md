# D12 六应用电子琴：精简整理版

本文件夹是 D12 的独立工程副本，适配 Tang Mega 60K + NEO Dock 31005，FPGA 为 GW5AT-60B。用户反馈 D12 已经上板且基本功能可以正常使用；具体各项长时间和手机测试以你们的实测记录为准。

## 快速找到需要的文件

1. **Gowin 工程**：[pressure_piano_touch.gprj](pressure_piano_touch.gprj)。用 Gowin FPGA Designer 打开；顶层为 `pressure_piano_28_touch_top`。
2. **已验证 D12 FPGA 位流**：[pressure_piano_touch.fs](impl/pnr/pressure_piano_touch.fs)，UserCode `0x0000925A`。可在 Gowin Programmer 中手动选择并进行 SRAM Program。此文件是原发布位流的逐字节副本。
3. **CH569 USB磁盘固件**：[piano_d12_ch569.hex](firmware/release/piano_d12_ch569.hex)。只用于板载 CH569，不能放进 Gowin Programmer。安装与恢复请先看 [CH569说明](docs/CH569_D12_UPGRADE.md)。
4. **游戏谱面**：[tf_card/SONGS](tf_card/SONGS)；七里香入门谱面是 `QLX_EASY.CSV`，请复制到TF卡的 `/SONGS` 目录。[关卡说明](docs/QLX_EASY_LEVEL_20261102.md)。
5. **D12说明**：[功能和谱面格式](docs/D12_DESIGN.md)、[上板步骤](docs/D12_上板步骤_20261102.md)、[赛事风险核对](docs/CONTEST_FAQ_RISK_REVIEW_20261102.md)。
6. **接线资料**：[28键整机接线](docs/hardware/28键整机接线指南_20261026.pdf)、[PCB4灯板接线](docs/hardware/PCB4接线指南_20261101.pdf)。两份图是相应日期的历史版本，最终信号分配以本工程 `constraints/pressure_piano_touch.cst` 和实际板卡为准。
7. **PCB4 原始资料**：[PCB4设计档案](docs/hardware/PCB4_20261021)，包含原始 `.epro2` 工程、PCB PDF 和当时的核对记录。

## 文件夹内容

- `src/`：HDL源码与必要的Gowin显示/时钟IP。
- `constraints/`：实际管脚与时序约束。
- `rom/`：音频、频谱、固件ROM和灯光数据。
- `firmware/`、`third_party/`：软核与CH569源码、第三方依赖和许可证；保留历史Helix依赖是为了既有构建与测试兼容，D12运行时不支持MP3解码。
- `sim/`、`tools/`：测试源码和常用构建、回归、关卡工具。Gowin、Vivado XSim和RISC-V GCC需在电脑上单独安装；`tools/compiler_path.json`记录的是整理时本机编译器路径，换电脑需更新。
- `reports/`：30项历史测试日志及结果、资源/时序与关卡验证记录。历史JSON里的绝对路径指向原工程，这是当时的证据，不是整理版依赖路径。
- `impl/`：过程配置、已发布925A位流、关键管脚及时序报告。新工程完整重建会重新生成其余实现文件。

## 重新编译与测试

- 直接在Gowin中打开工程并进行完整综合与布局布线；或从PowerShell在本目录运行 `./tools/run_implementation.ps1`。不要使用 `-PnROnly`，因为精简版没有复制旧综合网表。
- `./tools/run_d12_checks.ps1` 使用本机默认的 Vivado XSim 路径重新执行D12回归；换电脑须检查 `tools/run_tests.ps1` 的 `VivadoBin` 默认路径。
- `python tools/verify_package.py` 校验整理时的文件清单；如果之后主动修改源码或重新构建，对应文件的校验值变化是正常的。
- `python tools/build_media_firmware.py --verify` 可核对C源码是否复现既有ROM；`python tools/build_ch569.py` 只编译CH569固件，不会下载硬件。两者需要 `tools/compiler_path.json` 中的RISC-V GCC。
- 关卡重新生成/验证还需Python及脚本所需的numpy、Windows GCC和XSim。实际工具路径见脚本。

## 已保留与未带入的内容

本副本保留源码、约束、ROM、位流、固件、第三方授权、测试源码、关键历史日志和关卡。旧布局候选、SDF/巨大网表、重复波形、缓存、旧生成包和七里香预听音频未复制；原始工程仍保留在 `D:/FPGA/11_projects/pressure_piano_game_d12`。

D12当前耳机输出使用板载PT8211的LSBJ格式；**本整理版没有新增独立标准I2S引脚**。未通过本次整理执行硬件烧录。

位流 SHA-256：`DF0A54A400462D98CB56B3CD41DC43CC94525A5A5BDFA38AC76419CD7162C820`  
CH569 HEX SHA-256：`32A1A44B66B82F75DF07F9CBE4BD8E78CFBD2A951D2C342DD48AD58F77CDE68E`
