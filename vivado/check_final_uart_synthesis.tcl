# Static synthesis check for the final integrated board top. No simulation,
# implementation, bitstream generation, or report-document updates.
set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set out_dir [file normalize [file join $script_dir static_check_output]]
file mkdir $out_dir

create_project -in_memory -part xc7a100tfgg484-1
set_property target_language Verilog [current_project]
set_property include_dirs [file join $repo_dir src basic_components] [get_filesets sources_1]

set rtl_files {}
foreach pattern {
    src/*.v
    src/*.sv
    src/basic_components/*.v
    src/cache/*.v
    src/extension_components/*.v
    src/pipeline_cycle/*.v
    src/UART/*.sv
} {
    set rtl_files [concat $rtl_files [glob -nocomplain -directory $repo_dir $pattern]]
}

add_files -norecurse -fileset sources_1 $rtl_files
add_files -norecurse -fileset constrs_1 [file join $repo_dir xdc uart_pipeline_system.xdc]
set_property TOP uart_editable_pipeline_system_top [get_filesets sources_1]
update_compile_order -fileset sources_1

synth_design -top uart_editable_pipeline_system_top -part xc7a100tfgg484-1
report_utilization -file [file join $out_dir utilization_post_synth.rpt]
report_timing_summary -file [file join $out_dir timing_post_synth.rpt]
report_drc -file [file join $out_dir drc_post_synth.rpt]

puts "STATIC_SYNTHESIS_CHECK_PASSED"
close_project -delete
