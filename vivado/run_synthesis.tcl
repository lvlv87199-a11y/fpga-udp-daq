# Run Vivado synthesis and save the post-synthesis utilization report.

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
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "Synthesis status: $synth_status"
if {$synth_status ne "synth_design Complete!"} {
    close_project
    error "Vivado synthesis did not complete successfully: $synth_status"
}

open_run synth_1
report_utilization -hierarchical -file [file join $report_dir utilization_synth.rpt]
report_utilization -file [file join $report_dir utilization_synth_flat.rpt]
close_project

puts "Saved utilization reports under: $report_dir"
