# CH569 USB磁盘固件：准备与恢复

这是开发板 **CH569-USB3 Type-C** 的配套固件，不能用Gowin Programmer下载。Gowin Programmer仍只负责FPGA。屏幕TOUCH仍接J18、USBA-Switch朝FPGA，现有BL616下载器固件不改。

D12源码在 `firmware/ch569/`，构建入口 `tools/build_ch569.py`，输出 `reports/ch569_build/piano_d12_ch569.hex`。它使用现有RISC-V GCC，不需要安装MounRiver才能编译。

原厂CH569提供HSPI/CDC功能，更换为D12后此端口提供TF卡磁盘功能。保留官方恢复镜像 `docs/ch569_recovery/sipeed_factory_CH569_HSPI_USB.hex`。来源固定到Sipeed提交，哈希见同目录PROVENANCE。**这不是本块开发板的固件读回备份**。

## 进入实际刷写前

1. 先保存当前可用D11 FPGA位流与官方CH569恢复镜像，确认有恢复方法。
2. 按官方说明确认CH569 ISP能够识别芯片，记录设备信息及当前配置；工具若支持读取应用区，先保存读回文件和哈希。
3. 使用 **WCHISPStudio**。官方60K例程明确要求 `Chip Memory Allocation = RAMX96KB + ROM32KB`，`Download CFG Pin = PA13`。不要套用BL616的刷写工具和引脚配置。
4. 固件文件、配置页面和识别信息核对后再执行擦写；本次开发没有执行这一步。不要改USB JTAG下载器或FPGA启动Flash来尝试安装CH569固件。

测试期间先下载D12 FPGA，再升级CH569，并保持开发板DC供电。CH569与FPGA使用配套的引脚方向，避免混用其他会驱动HSPI/RGB连线的FPGA示例。若FPGA仍只在SRAM中、断电后会恢复旧镜像，重启时按官方建议先保持CH569复位/关闭，待D12 FPGA加载后再释放CH569；整机验证通过后再讨论D12 FPGA固化。

依据：[Sipeed60K CH569官方说明](https://github.com/sipeed/TangMega-60K-example/tree/main/ch569_hspi2cdc)。GPIO信号图参考NEO31005第21页，D12用到的13根板内连接见 `reports/d12_pin_mapping.json`。专用I2C/SSPI脚已避开，不需要改变FPGA的SSPI/I2C复用设置。

## 两份固件就绪后的使用顺序

1. 保持DC供电，先以SRAM方式下载经过验证的D12 FPGA位流，确认耳机、屏幕、实体键与触控正常。
2. 确认CH569已运行匹配的D12固件。未匹配时文件页面点击USB DISK显示 `USB LINK WAIT`，这是正常的保护状态。
3. 进入FILES，确保录音已完成、文件拷贝尚未开始，再点USB DISK。程序会同步、卸载TF卡，然后CH569才连接成USB磁盘。
4. iPhone用数据线连接 **CH569-USB3 Type-C**，在“文件→浏览”查找外部磁盘。可编辑 `/SONGS`、复制WAV录音和其他文件；D12只播放16位PCM WAV，不解码MP3。
5. 等待手机文件操作完成，按手机提供的弹出方式退出或先拔掉手机数据线，然后点FPGA的EJECT DISK。CH569先断开USB控制器、同步TF卡，再由FPGA重新挂载。FILES目录重新读取后才能开始新游戏或录音。

仅拔手机线不会直接把卡交还乐器，避免把USB暂停误当成安全卸载。拷贝时不要按EJECT或断电。

## 验证范围

已编译目标固件，并对USB控制请求、MSC/SCSI、CRC协议、异常恢复及文件系统互斥进行软件/RTL测试。实际CH569刷写、iPhone识别、TF卡写入后重读和断电保存仍要实板验证。官方恢复镜像已准备，不代表本板已完成备份或恢复测试。
