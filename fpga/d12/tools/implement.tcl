# Rebuild synthesis and place/route so the bitstream matches the current CST.
open_project pressure_piano_touch.gprj
set_option -top_module pressure_piano_28_touch_top
set_option -global_freq 50
set_option -vccx 1.8
set_option -use_cpu_as_gpio 1
set_option -gen_sdf 1
set_option -gen_verilog_sim_netlist 1
set_option -place_option 3
set_option -route_option 0
set_option -replicate_resources 1
run all
puts "CODEX_IMPLEMENTATION_FINISHED"
exit

