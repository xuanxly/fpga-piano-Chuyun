# 50MHz音频、30/150MHz视频、独立60MHz USB PLL。
create_clock -name sys_clk -period 20.000 [get_ports {sys_clk}]
create_generated_clock -name video_serial -source [get_ports {sys_clk}] -master_clock sys_clk -multiply_by 3 [get_pins {u_system/u_video_pll/PLLA_inst/CLKOUT0}]
create_generated_clock -name video_pixel -source [get_ports {sys_clk}] -master_clock sys_clk -divide_by 5 -multiply_by 3 [get_pins {u_system/u_video_pll/PLLA_inst/CLKOUT1}]
create_generated_clock -name usb_clk -source [get_ports {sys_clk}] -master_clock sys_clk -divide_by 5 -multiply_by 6 [get_pins {u_usb_pll/PLLA_inst/CLKOUT0}]
# 只切握手同步器第一级；快照数据在握手期间保持稳定，给出明确的跨域布线界限。
set_false_path -to [get_regs {u_system/u_snapshot/ack_meta*}]
set_false_path -to [get_regs {u_system/u_snapshot/req_meta*}]
set_max_delay 30 -from [get_regs {u_system/u_snapshot/held_data*}] -to [get_regs {u_system/u_snapshot/dst_data*}]
set_false_path -hold -from [get_regs {u_system/u_snapshot/held_data*}] -to [get_regs {u_system/u_snapshot/dst_data*}]
set_false_path -to [get_regs {u_touch_cdc/ack_meta*}]
set_false_path -to [get_regs {u_touch_cdc/req_meta*}]
set_max_delay 16.667 -from [get_regs {u_touch_cdc/held_data*}] -to [get_regs {u_touch_cdc/dst_*}]
set_false_path -hold -from [get_regs {u_touch_cdc/held_data*}] -to [get_regs {u_touch_cdc/dst_*}]
# PnR复制目的寄存器时以顶层连线touch_xs/ys命名，不能只匹配RTL的dst_*。
# 这些副本与dst_*有相同D和握手CE；held_data保持到ACK同步返回，采样时不会变化。
# 延续原邮箱16.667ns数据最大延迟，仅补齐原有异步Hold豁免的同类端点，不切同步器二级或普通逻辑。
set_max_delay 16.667 -from [get_regs {u_touch_cdc/held_data*}] -to [get_regs {u_touch_cdc/gowin_replicate_reg_touch_*}]
set_false_path -hold -from [get_regs {u_touch_cdc/held_data*}] -to [get_regs {u_touch_cdc/gowin_replicate_reg_touch_*}]
# USB线上信号异步于FPGA；只切各输入同步器的第一级。
# 两个输入端口在RTL中只通往各自同步器第一级；用端口约束避免依赖综合后的数组命名。
# 同步器第一级Q到第二级D仍正常分析时序。
set_false_path -from [get_ports {usb1_dp usb1_dm}]
# reset_sync本身的CLEAR端接异步请求（POR/外部复位/PLL LOCK）；其相位本来就不受目标时钟约束。
# 仅排除两个跨域复位同步器内部的异步清零引脚；pipe的D/Q路径以及同步复位输出仍正常检查。
set_false_path -to [get_pins {u_usb_reset/*/CLEAR u_system/u_pixel_reset/*/CLEAR}]

# D2诊断握手CDC：只排除第一级同步器；保持总线继续受最大布线延迟约束。
set_false_path -to [get_regs {u_usb_diag/u_cdc/ack_meta*}]
set_false_path -to [get_regs {u_usb_diag/u_cdc/req_meta*}]
set_max_delay 20 -from [get_regs {u_usb_diag/u_cdc/held_data*}] -to [get_regs {u_usb_diag/u_cdc/dst_data*}]
set_false_path -hold -from [get_regs {u_usb_diag/u_cdc/held_data*}] -to [get_regs {u_usb_diag/u_cdc/dst_data*}]
set_false_path -to [get_regs {u_usb_diag/lock_meta* u_usb_diag/reset_meta* u_usb_diag/error_meta*}]
set_false_path -to [get_regs {u_system/u_diag_snapshot/ack_meta*}]
set_false_path -to [get_regs {u_system/u_diag_snapshot/req_meta*}]
set_max_delay 30 -from [get_regs {u_system/u_diag_snapshot/held_data*}] -to [get_regs {u_system/u_diag_snapshot/dst_data*}]
set_false_path -hold -from [get_regs {u_system/u_diag_snapshot/held_data*}] -to [get_regs {u_system/u_diag_snapshot/dst_data*}]

# D4只切会话监视器的第一级；第二级同步器及长按/看门狗计数照常做STA。
set_false_path -to [get_regs {u_guard/beat_meta* u_guard/lock_meta* u_guard/key_meta*}]
# O为60MHz发送允许的异步单比特观测；只切usb_pin_meta第一级，第二级正常分析。
set_false_path -to [get_regs {usb_pin_meta*}]
# USB2异步接收仅进入PHY和独立观测各自第一级同步器，第二级仍正常分析。
set_false_path -from [get_ports {usb2_dp usb2_dm}]
# 会话许可使USB主机异步进入复位；仅排除复位同步器本身的异步清零脚。
set_false_path -to [get_pins {u_host_reset/*/CLEAR}]
# D7：仅排除输出级三只触发器的异步保护脚。allow释放经过host_rst_n同步，数据/CLK路径继续分析。
set_false_path -to [get_pins {u_usb2_pads/pad_oe_n*/PRESET u_usb2_pads/dp_tx_q*/CLEAR u_usb2_pads/dm_tx_q*/CLEAR}]

# D9媒体状态使用同一已验证邮箱结构：只切同步器首级，保持2211位总线30ns最大布线界限。
set_false_path -to [get_regs {u_system/u_media_snapshot/ack_meta*}]
set_false_path -to [get_regs {u_system/u_media_snapshot/req_meta*}]
set_max_delay 30 -from [get_regs {u_system/u_media_snapshot/held_data*}] -to [get_regs {u_system/u_media_snapshot/dst_data*}]
set_false_path -hold -from [get_regs {u_system/u_media_snapshot/held_data*}] -to [get_regs {u_system/u_media_snapshot/dst_data*}]
# 同一保持总线的像素侧副本也继承30ns最大延迟及异步Hold处理，不能漏掉工具生成的名称。
set_max_delay 30 -from [get_regs {u_system/u_media_snapshot/held_data*}] -to [get_regs {u_system/u_media_snapshot/gowin_replicate_reg_pixel_media*}]
set_false_path -hold -from [get_regs {u_system/u_media_snapshot/held_data*}] -to [get_regs {u_system/u_media_snapshot/gowin_replicate_reg_pixel_media*}]

# D9文本银行的消费确认仅跨一位，切第一级，第二级仍做STA。
set_false_path -to [get_regs {u_system/media.u_media/bank_meta*}]

# D9建立保护预算：保持实际50/30/60/150MHz不变，为全部已定义时钟加入0.300ns额外建立不确定度。
# 参照SUG940-2.0E第5.2.4节。此约束缩短可用数据时间，不能用false_path代替普通逻辑时序。
set_clock_uncertainty 0.300 -setup -from [get_clocks {sys_clk video_pixel video_serial usb_clk}]

# D12板内GPIO握手：三个异步控制输入只进入同步器首级；READY也可异步撤销输出。
# 首级Q到第二级D及全部协议/CPU路径继续按50MHz分析。
set_false_path -from [get_ports {ch_ready ch_rx_req ch_tx_ack}]
# 四位输入在REQ之前稳定，并保持到ACK；请求经过两级同步及两拍稳定等待才采样。
# 仍限制数据输入布线在20ns以内，禁止将整个握手模块切为false_path。
set_max_delay 20 -from [get_ports {ch_rx_data[*]}]
set_false_path -hold -from [get_ports {ch_rx_data[*]}]
# 数据比发送REQ提前一个50MHz周期，分别约束输出路径，保留足够的板内建立时间。
set_max_delay 10 -to [get_ports {ch_tx_data[*] ch_tx_req ch_rx_ack}]

# D13参数/计数快照继续使用保持总线握手；只切同步首级及异步时钟的Hold比较。
set_false_path -to [get_regs {u_system/u_extension_snapshot/ack_meta*}]
set_false_path -to [get_regs {u_system/u_extension_snapshot/req_meta*}]
set_max_delay 30 -from [get_regs {u_system/u_extension_snapshot/held_data*}] -to [get_regs {u_system/u_extension_snapshot/dst_data*}]
set_false_path -hold -from [get_regs {u_system/u_extension_snapshot/held_data*}] -to [get_regs {u_system/u_extension_snapshot/dst_data*}]
# I2S三输出均由同一50MHz域触发器驱动，限制输出布线，不放松内部Setup/Hold约束。
set_max_delay 10 -to [get_ports {i2s_bclk i2s_lrclk i2s_data}]
set_false_path -to [get_regs {u_runtime_bridge/ack_meta* u_runtime_bridge/req_meta*}]
set_max_delay 16.667 -from [get_regs {u_runtime_bridge/held_data*}] -to [get_regs {u_runtime_bridge/dst_data*}]
set_false_path -hold -from [get_regs {u_runtime_bridge/held_data*}] -to [get_regs {u_runtime_bridge/dst_data*}]
