# 自制电路板工程

PCB设计、原理图、PCB截图、网络记录和电路标注资料由**小谢**提供。

|目录|原生工程|有效布局|数量/用途|
|---|---|---|---|
|pressure|pressure.epro2|PCB2|4块同型板，每板7路FSR|
|control|control.epro2|PCB2|1块操作指示板|
|lighting|lighting.epro2|PCB1|1块4×7、一键四灯灯板|

使用嘉立创EDA专业版导入 `.epro2`。文件是提供资料中的2026-11-01原生导出，完整性与SHA-256见 `../../verification/`。仓库保留设计内容，未重新布线或改动原理图。

每个子目录的 `schematic.png` 和 `pcb.png` 为原始工程截图，`netlist.json` 为提供资料中的网络记录。详细接口见 [接线文档](../../docs/wiring.md)，工程导出与PNG对应文件见文件清单。

Gerber、钻孔、贴片生产BOM、坐标和DRC结果不在当前材料内。需要生产输出时，应从对应有效PCB布局导出并完成工程检查；截图和网络摘录不替代制造文件。
