# D13 精简开发工程

适配 Tang Mega 60K / GW5AT-60B + NEO Dock31005。当前发布版本 **C02F**，八应用、VERIFY、三种效果器、标准I2S及触控处理修复。

## 先打开这几个文件

1. [Gowin工程](pressure_piano_touch.gprj)：顶层`pressure_piano_28_touch_top`，用Gowin V1.9.11.03 Education打开。
2. [已发布FPGA位流](impl/pnr/pressure_piano_touch.fs)：User Code **0x0000C02F**，与原发布逐字节相同；下载说明见[上板步骤](docs/D13_上板步骤.md)。
3. [功能与I2S接线](docs/D13_SCOPE.md)、[触控自检](docs/TOUCH_SELF_CHECK_D13.md)、[赛题核对](docs/D13_CONTEST_RECHECK.md)。
4. [CH569配套HEX](firmware/release/piano_d12_ch569.hex)沿用D12，供既有USB磁盘使用。[CH569升级说明](docs/CH569_D12_UPGRADE.md)；此HEX不交给Gowin Programmer。
5. [谱面目录](tf_card/SONGS)、[接线PDF](docs/hardware/28键整机接线指南_20261026.pdf)、[灯板PDF](docs/hardware/PCB4接线指南_20261101.pdf)、[原理图与PCB档案](docs/hardware/PCB4_20261021)。历史接线PDF未包含D13新增I2S，新增引脚以D13_SCOPE及当前CST为准。

## 目录用途

- `src`、`constraints`、`rom`：FPGA源码、引脚/时序及全部必要ROM，保持原C02F内容。
- `firmware`、`third_party`：软核/CH569源码、已发布HEX、依赖及许可证；Gowin直接构建使用既有ROM，无须先编译C。保留Helix依赖资料不代表D13运行时支持MP3。
- `sim`：测试源码/参考及测试数据；`tools`：构建、回归和关卡工具。
- `docs`：说明和硬件资料；`tf_card`：可复制到卡上的数据。
- `impl`：过程配置、C02F位流和报告；`reports`：验证证据。
- 精简版不带失败候选、大型SDF/综合网表、仿真运行缓存或旧版迁移/发布脚本。保留34项历史通过日志和最终时序/引脚报告。

## 后续开发与检查

在此目录打开工程修改即可，工程58项引用均为包内相对路径。Gowin与Vivado XSim仍需电脑上安装；C编译工具位置见`tools/compiler_path.json`，换电脑按实际位置更新。

- 完整重建FPGA：Gowin依次综合与布局布线，或PowerShell执行`./tools/run_implementation.ps1`。首次重建使用完整流程，避免复用归档路径中的旧网表。
- 当前34项回归：`./tools/run_d13_regression.ps1`，默认Vivado2025.2路径可通过`-VivadoBin`修改；新日志另存`reports/retest_d13_时间`。
- 原始交付完整性：`python tools/verify_package_d13.py`；主动修改源码/重新构建后清单不再匹配属于正常情况。
- 核对软核ROM：`python tools/build_media_firmware.py --verify`；CH569源码编译：`python tools/build_ch569.py`。均不刷写硬件。

报告中的旧绝对路径只是历史记录；历史发布/审计脚本有基线目录假设，本文件夹整理后的独立校验入口是`verify_package_d13.py`。精简版采用上述当前入口，完整历史放在另一个完整版文件夹。

## 验证口径

原发布34项RTL、独立音频模型、真实C/FatFs卡模型、ROM及完整Gowin实现已通过。Setup/Hold最小+2.529/+0.140ns，BSRAM103/118，DSP86/118，0.300ns额外建立预算保留，PR1014告警仍有记录。本次整理的具体检查见[整理验证](reports/package_checks/整理验证.md)；不将复制历史日志视为本次重跑34项或重新PnR。

未自动下载FPGA、CH569或Flash；D13触控改善、音效听感与模拟端到端延迟仍待实板验收。

FPGA SHA256：`065BDDD3654E0265ABBB3CC54C5DD1021EBD49B6E1336ED688BE5E37649A1E46`  
CH569 HEX SHA256：`32A1A44B66B82F75DF07F9CBE4BD8E78CFBD2A951D2C342DD48AD58F77CDE68E`
