# Non-project batch build for Cmod A7.
#
#   vivado -mode batch -source build.tcl                          ;# A7-35T, N=4
#   vivado -mode batch -source build.tcl -tclargs xc7a15tcpg236-1 ;# A7-15T
#   vivado -mode batch -source build.tcl -tclargs xc7a35tcpg236-1 8
#
# Outputs to fpga/cmod_a7/out/: cmod_a7_top.bit, timing + utilization reports.

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize "$script_dir/../.."]
set out_dir    "$script_dir/out"

set part xc7a35tcpg236-1
set n    4
if { $argc >= 1 } { set part [lindex $argv 0] }
if { $argc >= 2 } { set n    [lindex $argv 1] }

puts "INFO: building cmod_a7_top for $part with N=$n"
file mkdir $out_dir

read_verilog -sv [list \
  "$repo_root/rtl/mac_pe.sv" \
  "$repo_root/rtl/systolic_array.sv" \
  "$repo_root/rtl/uart.sv" \
  "$repo_root/rtl/uart_host_if.sv" \
  "$repo_root/rtl/tokyo_mac_top.sv" \
  "$script_dir/cmod_a7_top.sv" \
]
read_xdc [list "$script_dir/cmod_a7.xdc"]

synth_design -top cmod_a7_top -part $part -generic N=$n
opt_design
place_design
route_design

report_timing_summary -file "$out_dir/timing_summary.rpt"
report_utilization    -file "$out_dir/utilization.rpt"

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "INFO: worst negative slack (setup) = $wns ns"
if { $wns < 0 } {
  puts "ERROR: timing not met"
  exit 1
}

write_bitstream -force "$out_dir/cmod_a7_top.bit"
puts "INFO: wrote $out_dir/cmod_a7_top.bit"
