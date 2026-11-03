# 系统时钟来自官方示例的 50 MHz sys_clk；真实硬件仍需核对。
create_clock -name sys_clk -period 20.000 [get_ports {sys_clk}]
# ADC、DAC 与控件的板级输入输出延迟待接线和器件时序核对后补齐。
# 此处不以大范围 false_path 或 multicycle 掩盖内部时序问题。

# PLL outputs are related to each other; never declare pixel and serial clocks asynchronous.
create_generated_clock -name video_serial -source [get_ports {sys_clk}] -master_clock sys_clk -multiply_by 3 [get_pins {u_video_pll/PLLA_inst/CLKOUT0}]
create_generated_clock -name video_pixel -source [get_ports {sys_clk}] -master_clock sys_clk -divide_by 5 -multiply_by 3 [get_pins {u_video_pll/PLLA_inst/CLKOUT1}]
# The held snapshot bus is stable through a two-flop request/acknowledge handshake.
set_false_path -to [get_regs {u_snapshot/ack_meta*}]
set_false_path -to [get_regs {u_snapshot/req_meta*}]
set_false_path -to [get_regs {u_diag_snapshot/ack_meta*}]
set_false_path -to [get_regs {u_diag_snapshot/req_meta*}]
set_max_delay 30 -from [get_regs {u_diag_snapshot/held_data*}] -to [get_regs {u_diag_snapshot/dst_data*}]
set_false_path -hold -from [get_regs {u_diag_snapshot/held_data*}] -to [get_regs {u_diag_snapshot/dst_data*}]
set_max_delay 30 -from [get_regs {u_snapshot/held_data*}] -to [get_regs {u_snapshot/dst_data*}]
set_false_path -hold -from [get_regs {u_snapshot/held_data*}] -to [get_regs {u_snapshot/dst_data*}]
