# D13 工程入口

[返回项目首页](../README.md) · [接线说明](../docs/wiring.md) · [软件功能与实拍](../docs/software.md)

当前工程为 `d13/`，包含 HDL、VexRiscv 软核程序、约束、ROM、CH569 固件、仿真与验证记录。`d12/` 保留历史版本；附加关卡位于 `levels/`。

1. 用 Gowin FPGA Designer 打开 [pressure_piano_touch.gprj](d13/pressure_piano_touch.gprj)，顶层为 `pressure_piano_28_touch_top`，平台为 Tang Mega 60K + NEO DOCK 31005。
2. 查看 [管脚约束](d13/constraints/pressure_piano_touch.cst)、[原始工程说明](d13/README_请先看.md) 与 [D13功能范围](d13/docs/D13_SCOPE.md)。
3. [发布位流](d13/impl/pnr/pressure_piano_touch.fs) 的 UserCode 为 `0x0000C02F`。D13 沿用 [piano_d12_ch569.hex](d13/firmware/release/piano_d12_ch569.hex)，文件名为配套固件版本，并非 FPGA 工程版本。
4. [原有关卡](d13/tf_card/SONGS/) 以及 [三首附加关卡](levels/SONGS/) 中的 CSV 均复制到 TF 卡 `/SONGS/`。附加关卡均为白键右手旋律；《菊次郎的夏天》为所给第 1 页主题片段，范围见 [说明](levels/使用说明.md)。

## 功能与验证

D13 提供八个 HOME 入口、28 声部五音色、三种硬件效果、WAV 录放、CSV 音游、双向 USB 磁盘、触控连续性处理、VERIFY 监测和标准 I²S。VERIFY 的 32 路为独立测试音引擎；正常演奏配置为 28 声部。

- 原包的构建与回归依赖 Gowin、XSim、RISC-V GCC 等工具；换电脑时检查 `tools/compiler_path.json` 及脚本里的工具位置。
- 归档执行了文件、项目相对引用与历史日志校验；本次整理未重新运行综合、全套仿真或烧录。34 项日志为随包历史结果，不能替代整机专项实测。
- `tools/verify_package_d13.py` 提供包校验，记录见 `reports/d13_verification.json`。
- CH569 使用 USB MSC 块设备双向复制 SD 文件。录音工作室网页的 Web Serial CDC 应用协议仍需单独适配。
- FPGA 位流 SHA-256：`065bdd3654e0265abbb3cc54c5dd1021ebd49b6e1336ed688be5e37649a1e46`。

## 第三方代码

各版本 `third_party/` 保留依赖的原始许可与声明；仓库尚未为项目原创资料指定统一开源许可证。
