# 引脚核对参考

`tang_mega_60K_pins.cst` 复制自本机既有参考资料：

`D:/Gowin/.codex_tmp/pins_31005_20261011/tang_mega_60K_pins.cst`

SHA256：`DCACED4A5D15D60A3615190138AD3522B562C82748E35FFD150139BC7542FF4C`。

该参考表的 `cmos_pclk` 使用 AB20 / LVCMOS33。结合 NEO_31005 原理图第7/19页，链路为 J8-6 / PMOD1_IO7 → CAM0_PCLK / SDRAM1_WE → BTB J2-15 → AB20；J14-27也在此网络。

这里只存核对依据，不加入Gowin工程，不与实际 `constraints/pressure_piano.cst` 同时加载。`tools/audit28_pins.py` 使用项目内副本，便于工程移到其他目录后继续静态核对。
