set script_dir [file dirname [file normalize [info script]]]
set project_file [file join $script_dir Vivado.xpr]
set allowed_tops {
    tb_uart_program_packet_rx
    tb_uart_program_loader
    tb_uart_pipeline_system
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

if {[catch {
    open_project $project_file
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
