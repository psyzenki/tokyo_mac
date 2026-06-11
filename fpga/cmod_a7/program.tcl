# Program a connected Cmod A7 over JTAG (volatile - lost on power cycle).
#
#   vivado -mode batch -source program.tcl
#   vivado -mode batch -source program.tcl -tclargs path/to/other.bit

set script_dir [file dirname [file normalize [info script]]]
set bit "$script_dir/out/cmod_a7_top.bit"
if { $argc >= 1 } { set bit [lindex $argv 0] }

if { ![file exists $bit] } {
  puts "ERROR: bitstream not found: $bit (run build.tcl first)"
  exit 1
}

open_hw_manager
connect_hw_server
if { [llength [get_hw_targets -quiet]] == 0 } {
  puts "ERROR: no JTAG target found - is the Cmod A7 plugged in?"
  exit 1
}
open_hw_target

set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
puts "INFO: found device: [get_property PART $dev]"

set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
puts "INFO: programmed $bit"
close_hw_manager
