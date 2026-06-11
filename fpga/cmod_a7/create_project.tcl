# Generate a Vivado GUI project (vivado_proj/tokyo_mac.xpr) that references
# the repo sources in place. Regenerate any time; vivado_proj/ is gitignored.
#
#   vivado -mode batch -source create_project.tcl
#   vivado -mode batch -source create_project.tcl -tclargs xc7a15tcpg236-1

set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize "$script_dir/../.."]
set proj_dir   "$script_dir/vivado_proj"

set part xc7a35tcpg236-1
if { $argc >= 1 } { set part [lindex $argv 0] }

create_project tokyo_mac $proj_dir -part $part -force

add_files -norecurse [list \
  "$repo_root/rtl/mac_pe.sv" \
  "$repo_root/rtl/systolic_array.sv" \
  "$repo_root/rtl/uart.sv" \
  "$repo_root/rtl/uart_host_if.sv" \
  "$repo_root/rtl/tokyo_mac_top.sv" \
  "$script_dir/cmod_a7_top.sv" \
]
add_files -fileset constrs_1 -norecurse [list "$script_dir/cmod_a7.xdc"]
set_property top cmod_a7_top [current_fileset]

add_files -fileset sim_1 -norecurse [list \
  "$repo_root/tb/mac_pe_tb.sv" \
  "$repo_root/tb/systolic_array_tb.sv" \
  "$repo_root/tb/systolic_array_top.sv" \
  "$repo_root/tb/systolic_ref_model.sv" \
  "$repo_root/tb/tokyo_mac_sys_tb.sv" \
  "$repo_root/tb/tokyo_mac_top_tb.sv" \
  "$repo_root/tb/uart_tb.sv" \
]
set_property top tokyo_mac_top_tb [get_filesets sim_1]
# RTL files carry no timescale; give xsim a default so tb elaboration works
set_property -name {xsim.elaborate.xelab.more_options} \
  -value {-timescale 1ns/1ps} -objects [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "INFO: project written to $proj_dir/tokyo_mac.xpr"
