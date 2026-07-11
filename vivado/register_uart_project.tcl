set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set project_file [file join $script_dir Vivado.xpr]

proc register_sv {fileset_name path} {
    if {![file isfile $path]} {
        error "Missing SystemVerilog file: $path"
    }
    set fileset [get_filesets $fileset_name]
    set object [get_files -quiet -of_objects $fileset $path]
    if {[llength $object] == 0} {
        add_files -norecurse -fileset $fileset_name $path
        set object [get_files -quiet -of_objects $fileset $path]
    }
    if {[llength $object] != 1} {
        error "Cannot uniquely register SystemVerilog file: $path"
    }
    set_property FILE_TYPE SystemVerilog $object
}

open_project $project_file

foreach relative_path {
    src/UART/uart_rx_byte.sv
    src/UART/uart_tx_byte.sv
    src/UART/uart_program_packet_rx.sv
    src/UART/uart_program_loader.sv
    src/UART/uart_response_packet_tx.sv
    src/uart_editable_pipeline_system_top.sv
} {
    register_sv sources_1 [file normalize [file join $repo_dir $relative_path]]
}

foreach relative_path {
    tb/tb_uart_program_packet_rx.sv
    tb/tb_uart_program_loader.sv
    tb/tb_uart_pipeline_system.sv
} {
    set tb_path [file normalize [file join $repo_dir $relative_path]]
    register_sv sim_1 $tb_path
    set tb_object [get_files -quiet -of_objects [get_filesets sim_1] $tb_path]
    set_property USED_IN_SYNTHESIS false $tb_object
    set_property USED_IN_IMPLEMENTATION false $tb_object
}

set constraints_fileset [get_filesets constrs_1]
foreach relative_path {
    xdc/minisys_template.xdc
    xdc/editable_minisys_template.xdc
} {
    set old_xdc [file normalize [file join $repo_dir $relative_path]]
    set old_object [get_files -quiet -of_objects $constraints_fileset $old_xdc]
    if {[llength $old_object] != 0} {
        remove_files $old_object
    }
}

set uart_xdc [file normalize [file join $repo_dir xdc uart_pipeline_system.xdc]]
if {![file isfile $uart_xdc]} {
    error "Missing constraints file: $uart_xdc"
}
set uart_xdc_object [get_files -quiet -of_objects $constraints_fileset $uart_xdc]
if {[llength $uart_xdc_object] == 0} {
    add_files -norecurse -fileset constrs_1 $uart_xdc
    set uart_xdc_object [get_files -quiet -of_objects $constraints_fileset $uart_xdc]
}
if {[llength $uart_xdc_object] != 1} {
    error "Cannot uniquely register constraints file: $uart_xdc"
}
set_property USED_IN_SYNTHESIS true $uart_xdc_object
set_property USED_IN_IMPLEMENTATION true $uart_xdc_object

set_property TOP_AUTO_SET 0 [get_filesets sources_1]
set_property TOP uart_editable_pipeline_system_top [get_filesets sources_1]
set_property SOURCE_SET sources_1 [get_filesets sim_1]
set_property TOP_AUTO_SET 0 [get_filesets sim_1]
set_property TOP tb_uart_pipeline_system [get_filesets sim_1]
set_property -name xsim.elaborate.xelab.more_options \
    -value {--timescale 1ns/1ps} -objects [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Registered UART loader sources. Synthesis top: uart_editable_pipeline_system_top"
puts "Active constraint file: $uart_xdc"
save_project
close_project
