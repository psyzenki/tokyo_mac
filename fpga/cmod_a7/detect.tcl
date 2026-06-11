# Report the part of a connected JTAG device (used to pick 35T vs 15T).
open_hw_manager
connect_hw_server
if { [llength [get_hw_targets -quiet]] == 0 } {
  puts "DETECT: no JTAG target connected"
} else {
  open_hw_target
  foreach dev [get_hw_devices] {
    puts "DETECT: device [get_property PART $dev]"
  }
}
close_hw_manager
