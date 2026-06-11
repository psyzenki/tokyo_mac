# Write the bitstream into the Cmod A7's QSPI flash (MX25L3233F) so the FPGA
# configures itself at power-on - survives unplugging, no PC needed.
#
#   vivado -mode batch -source flash.tcl
#
# Uses out/cmod_a7_top.bit (run build.tcl first). Ends by booting the FPGA
# from flash, so the new image is live immediately.

set script_dir [file dirname [file normalize [info script]]]
# write_cfgmem's -loadbit string splits on spaces, so use paths relative to
# the script dir (the repo path may contain spaces).
cd $script_dir

set bit "out/cmod_a7_top.bit"
set mcs "out/cmod_a7_top.mcs"
# Cmod A7 carries an MX25L3233F; newer Vivado dropped that entry, and the
# command-compatible MX25L3273F is the recommended substitute.
set flash_part mx25l3273f-spi-x1_x2_x4

if { ![file exists $bit] } {
  puts "ERROR: bitstream not found: $script_dir/$bit (run build.tcl first)"
  exit 1
}

write_cfgmem -force -format mcs -size 4 -interface SPIx4 \
  -loadbit "up 0x0 $bit" -file $mcs

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

create_hw_cfgmem -hw_device $dev [lindex [get_cfgmem_parts $flash_part] 0]
set cfgmem [current_hw_cfgmem]
set_property PROGRAM.FILES [list "$script_dir/$mcs"] $cfgmem
set_property PROGRAM.ADDRESS_RANGE  {use_file} $cfgmem
set_property PROGRAM.ERASE          1 $cfgmem
set_property PROGRAM.CFG_PROGRAM    1 $cfgmem
set_property PROGRAM.VERIFY         1 $cfgmem
set_property PROGRAM.CHECKSUM       0 $cfgmem

# Programming the flash goes through a JTAG helper bitstream
create_hw_bitstream -hw_device $dev [get_property PROGRAM.HW_CFGMEM_BITFILE $dev]
program_hw_devices $dev
program_hw_cfgmem -hw_cfgmem $cfgmem

# Reconfigure the FPGA from the freshly written flash
boot_hw_device $dev
puts "INFO: flash programmed and FPGA booted from flash"
close_hw_manager
