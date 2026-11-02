if {[catch {open_project pressure_piano_touch.gprj} err]} {
    puts stderr "OPEN_PROJECT_FAILED: $err"
    exit 1
}
puts "PASS_PACKAGE_GOWIN_OPEN_PROJECT"
exit
