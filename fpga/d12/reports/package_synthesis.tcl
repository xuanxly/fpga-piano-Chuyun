if {[catch {open_project pressure_piano_touch.gprj} err]} { puts stderr "FAIL_OPEN $err"; exit 1 }
set_option -top_module pressure_piano_28_touch_top
set_option -global_freq 50
set_option -vccx 1.8
set_option -use_cpu_as_gpio 1
if {[catch {run syn} err]} { puts stderr "FAIL_SYN $err"; exit 1 }
puts "PASS_PACKAGE_GOWIN_SYNTHESIS"
exit
