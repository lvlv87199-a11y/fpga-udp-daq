# Add the Day23 XDC constraint file to the existing Vivado project.

set script_dir [file normalize [file dirname [info script]]]
set project_file [file join $script_dir daq_top_project fpga_udp_daq.xpr]
set xdc_file [file join $script_dir daq_top.xdc]

if {![file exists $project_file]} {
    puts "ERROR: Vivado project not found: $project_file"
    exit 2
}
if {![file exists $xdc_file]} {
    puts "ERROR: XDC file not found: $xdc_file"
    exit 3
}

open_project $project_file
set existing [get_files -quiet $xdc_file]
if {[llength $existing] == 0} {
    add_files -fileset constrs_1 -norecurse $xdc_file
}
update_compile_order -fileset sources_1
close_project

puts "Added constraint file: $xdc_file"
