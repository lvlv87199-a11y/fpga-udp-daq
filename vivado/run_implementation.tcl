# Run Vivado implementation through route_design and save timing reports.
# Bitstream generation is intentionally not requested on Day24.

set script_dir [file normalize [file dirname [info script]]]
set project_file [file join $script_dir daq_top_project fpga_udp_daq.xpr]
set report_dir [file join $script_dir reports]
file mkdir $report_dir

if {![file exists $project_file]} {
    puts "ERROR: Vivado project not found: $project_file"
    exit 2
}

open_project $project_file
update_compile_order -fileset sources_1
reset_run impl_1
launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "Implementation status: $impl_status"
if {![string match "*Complete!*" $impl_status]} {
    close_project
    error "Vivado implementation did not complete successfully: $impl_status"
}

open_run impl_1
report_timing_summary -delay_type min_max -file [file join $report_dir timing_summary_impl.rpt]
report_timing -max_paths 10 -sort_by slack -file [file join $report_dir timing_paths_impl.rpt]
report_utilization -hierarchical -file [file join $report_dir utilization_impl.rpt]
report_clock_utilization -file [file join $report_dir clock_utilization_impl.rpt]
close_project

puts "Saved implementation reports under: $report_dir"
