set script_dir [file dirname [file normalize [info script]]]
set project_root [file normalize [file join $script_dir ".."]]
set project_dir [file join $script_dir "cached_pipeline_project"]

create_project cached_pipeline_cpu $project_dir -part xc7a100tfgg484-1 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set basic_dir [file join $project_root "src" "basic_components"]
set cache_dir [file join $project_root "src" "cache"]
set pipeline_dir [file join $project_root "src" "pipeline_cycle"]
set extension_dir [file join $project_root "src" "extension_components"]

add_files [glob -nocomplain [file join $basic_dir "*.v"]]
add_files [glob -nocomplain [file join $cache_dir "*.v"]]
add_files [glob -nocomplain [file join $pipeline_dir "*.v"]]
add_files [glob -nocomplain [file join $extension_dir "*.v"]]
add_files [file join $project_root "src" "cached_pipeline_minisys_top.v"]

set_property include_dirs [list $basic_dir] [get_filesets sources_1]
set_property top cached_pipeline_minisys_top [get_filesets sources_1]

add_files -fileset constrs_1 [file join $project_root "xdc" "cached_pipeline_minisys_template.xdc"]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {![string match "*Complete*" [get_property STATUS [get_runs synth_1]]]} {
    error "Synthesis did not complete"
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {![string match "*Complete*" [get_property STATUS [get_runs impl_1]]]} {
    error "Implementation did not complete"
}

open_run impl_1
report_timing_summary -file [file join $project_dir "cached_pipeline_timing_summary.rpt"]
report_utilization -file [file join $project_dir "cached_pipeline_utilization.rpt"]

set timing_path [get_timing_paths -delay_type max -max_paths 1]
if {[llength $timing_path] > 0} {
    puts "CACHE_BOARD_WNS=[get_property SLACK $timing_path]"
}
set bitstream_path [file join $project_dir "cached_pipeline_cpu.runs" "impl_1" "cached_pipeline_minisys_top.bit"]
puts "CACHE_BOARD_BITSTREAM=$bitstream_path"
