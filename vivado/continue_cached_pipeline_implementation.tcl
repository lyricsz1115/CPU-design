set script_dir [file dirname [file normalize [info script]]]
set project_file [file join $script_dir "cached_pipeline_project" "cached_pipeline_cpu.xpr"]

open_project $project_file

if {![string match "*Complete*" [get_property STATUS [get_runs synth_1]]]} {
    error "synth_1 is not complete; run create_cached_pipeline_project.tcl first"
}

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if {![string match "*Complete*" [get_property STATUS [get_runs impl_1]]]} {
    error "Implementation did not complete"
}

open_run impl_1
set report_dir [file dirname $project_file]
report_timing_summary -file [file join $report_dir "cached_pipeline_timing_summary.rpt"]
report_utilization -file [file join $report_dir "cached_pipeline_utilization.rpt"]

set timing_path [get_timing_paths -delay_type max -max_paths 1]
if {[llength $timing_path] > 0} {
    puts "CACHE_BOARD_WNS=[get_property SLACK $timing_path]"
}
set bitstream_path [file join $report_dir "cached_pipeline_cpu.runs" "impl_1" "cached_pipeline_minisys_top.bit"]
puts "CACHE_BOARD_BITSTREAM=$bitstream_path"
