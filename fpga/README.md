# D12 工程入口

[返回项目首页](../README.md) · [接线说明](../docs/wiring.md) · [软件功能与实拍](../docs/software.md)

本目录归档用户提供的 `pressure_piano_D12_clean_20261102.zip` 内容，逐文件保持原始字节。D13由项目成员继续开发，本包不将D13功能计入D12。

1. 用 Gowin FPGA Designer 打开 [pressure_piano_touch.gprj](d12/pressure_piano_touch.gprj)，顶层为 `pressure_piano_28_touch_top`，平台为Tang Mega 60K + NEO Dock 31005。
2. 查看 [管脚约束](d12/constraints/pressure_piano_touch.cst)、[原始工程说明](d12/README_请先看.md) 与 [D12设计说明](d12/docs/D12_DESIGN.md)。
3. [已发布FPGA位流](d12/impl/pnr/pressure_piano_touch.fs) 的UserCode为 `0x0000925A`；[CH569 HEX](d12/firmware/release/piano_d12_ch569.hex) 用于板载CH569，安装与恢复按 [固件说明](d12/docs/CH569_D12_UPGRADE.md) 操作。
4. [游戏CSV谱面](d12/tf_card/SONGS) 复制到TF卡的 `/SONGS` 目录。

## 复现与验证

- 原包的构建和回归脚本依赖本机Gowin、XSim、RISC-V GCC等工具。换电脑时检查 `tools/compiler_path.json` 和脚本中的工具位置。
- 本次归档未重新运行综合、回归或烧录。30项历史测试日志及资源时序数据保留在 `d12/reports/` 和 `d12/impl/`，文件校验见仓库 `verification/`。
- D12采用CH569 USB MSC磁盘读写，实现电脑与SD卡双向文件复制；录音工作室网页使用的Web Serial CDC协议仍需另外适配。
- 原包历史硬件PDF、PCB档案保留其原日期与版本，信号分配以本次D12 CST及实际接线为准。

## 第三方代码

`d12/third_party/`保留各依赖的原始许可和声明。本仓库未替项目原创资料指定统一开源许可证。
