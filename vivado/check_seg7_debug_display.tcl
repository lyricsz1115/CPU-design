set script_dir [file dirname [file normalize [info script]]]
set project_file [file join $script_dir Vivado.xpr]

open_project $project_file
update_compile_order -fileset sources_1
synth_design -rtl -name rtl_seg7_debug_check \
    -top uart_editable_pipeline_system_top \
    -part xc7a100tfgg484-1
puts "RTL_SEG7_DEBUG_DISPLAY_CHECK_PASS"
close_project
