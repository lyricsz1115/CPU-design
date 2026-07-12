set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set project_file [file join $script_dir Vivado.xpr]

proc register_verilog {fileset_name path} {
    if {![file isfile $path]} {
        error "Missing Verilog file: $path"
    }
    set fileset [get_filesets $fileset_name]
    set object [get_files -quiet -of_objects $fileset $path]
    if {[llength $object] == 0} {
        add_files -norecurse -fileset $fileset_name $path
        set object [get_files -quiet -of_objects $fileset $path]
    }
    if {[llength $object] != 1} {
        error "Cannot uniquely register Verilog file: $path"
    }
}

open_project $project_file
foreach relative_path {
    src/cache/data_cache.v
    src/cache/cache_memory_adapter.v
} {
    register_verilog sources_1 [file normalize [file join $repo_dir $relative_path]]
}
update_compile_order -fileset sources_1
synth_design -rtl -name rtl_seg7_debug_check \
    -top uart_editable_pipeline_system_top \
    -part xc7a100tfgg484-1
puts "RTL_SEG7_DEBUG_DISPLAY_CHECK_PASS"
close_project
