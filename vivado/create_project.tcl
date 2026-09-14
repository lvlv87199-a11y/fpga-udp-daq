# Create the Day22 Vivado RTL project for fpga-udp-daq.
#
# Usage from a Vivado Tcl/batch shell:
#   vivado -mode batch -source vivado/create_project.tcl -tclargs --list "*xc7a*"
#   vivado -mode batch -source vivado/create_project.tcl -tclargs xc7a100tcsg324-1
#
# The project is intentionally created without board files. Select a part that
# is installed in the local Vivado device catalog.

set script_dir [file normalize [file dirname [info script]]]
set repo_root  [file normalize [file join $script_dir ..]]
set project_dir [file join $script_dir daq_top_project]
set project_name fpga_udp_daq

if {$argc >= 1 && [lindex $argv 0] eq "--list"} {
    if {$argc >= 2} {
        set pattern [lindex $argv 1]
    } else {
        set pattern "*"
    }
    puts "Installed parts matching $pattern:"
    foreach part [get_parts -quiet $pattern] {
        puts $part
    }
    exit 0
}

if {$argc < 1} {
    puts "ERROR: provide an installed FPGA part, or use --list <pattern>."
    puts "Example: -tclargs xc7a100tcsg324-1"
    exit 2
}

set part [lindex $argv 0]
set force_project 0
if {$argc >= 2 && [lindex $argv 1] eq "--force"} {
    set force_project 1
}

if {[llength [get_parts -quiet $part]] == 0} {
    puts "ERROR: FPGA part '$part' is not installed in this Vivado device catalog."
    puts "Use -tclargs --list \"*xc7a*\" to inspect installed parts."
    exit 3
}

if {[file exists $project_dir] && !$force_project} {
    puts "ERROR: project directory already exists: $project_dir"
    puts "Delete it deliberately or rerun with a second argument --force."
    exit 4
}

create_project $project_name $project_dir -part $part -force

set rtl_files [list \
    [file join $repo_root rtl daq_ctrl.sv] \
    [file join $repo_root rtl sample_generator.sv] \
    [file join $repo_root rtl sync_fifo.sv] \
    [file join $repo_root rtl packetizer.sv] \
    [file join $repo_root rtl daq_top.sv] \
]

foreach rtl_file $rtl_files {
    if {![file exists $rtl_file]} {
        puts "ERROR: missing RTL source: $rtl_file"
        exit 5
    }
    add_files -fileset sources_1 -norecurse $rtl_file
}

set_property top daq_top [current_fileset]
set_property top_file [file join $repo_root rtl daq_top.sv] [current_fileset]
update_compile_order -fileset sources_1

puts "Created Vivado project: [file join $project_dir ${project_name}.xpr]"
puts "Target part: $part"
puts "Top module: daq_top"
puts "RTL source count: [llength $rtl_files]"

close_project
