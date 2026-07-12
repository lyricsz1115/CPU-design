set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set project_file [file join $script_dir Vivado.xpr]
set allowed_tops {
    tb_uart_program_packet_rx
    tb_uart_program_loader
    tb_uart_pipeline_system
    tb_pipeline
    tb_mul_div
    tb_data_cache
    tb_cached_pipeline
}

if {[llength $argv] != 1} {
    puts stderr "Usage: vivado -mode batch -source run_uart_tb.tcl -tclargs <testbench>"
    exit 2
}

set testbench [lindex $argv 0]
if {[lsearch -exact $allowed_tops $testbench] < 0} {
    puts stderr "Unsupported testbench: $testbench"
    exit 2
}

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

if {[catch {
    open_project $project_file
    foreach relative_path {
        src/cache/data_cache.v
        src/cache/cache_memory_adapter.v
        src/cached_pipeline_minisys_top.v
    } {
        register_sv sources_1 [file normalize [file join $repo_dir $relative_path]]
    }
    foreach relative_path {
        tb/tb_uart_program_packet_rx.sv
        tb/tb_uart_program_loader.sv
        tb/tb_uart_pipeline_system.sv
        tb/tb_pipeline.v
        tb/tb_mul_div.v
        tb/tb_data_cache.v
        tb/tb_cached_pipeline.v
    } {
        register_sv sim_1 [file normalize [file join $repo_dir $relative_path]]
    }
    set_property source_mgmt_mode None [current_project]
    set_property SOURCE_SET sources_1 [get_filesets sim_1]
    set_property TOP_AUTO_SET 0 [get_filesets sim_1]
    set_property TOP $testbench [get_filesets sim_1]
    set_property -name xsim.elaborate.xelab.more_options \
        -value {--timescale 1ns/1ps} -objects [get_filesets sim_1]
    set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
    update_compile_order -fileset sim_1
    launch_simulation -simset sim_1 -mode behavioral
    run all
    close_sim
    set_property TOP tb_uart_pipeline_system [get_filesets sim_1]
    close_project
} message options]} {
    puts stderr $message
    catch {close_sim}
    catch {close_project}
    exit 1
}

exit 0
