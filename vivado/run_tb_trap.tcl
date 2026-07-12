# ============================================================================
# run_tb_trap.tcl — 中断系统独立仿真脚本
# 用法: vivado -mode batch -source vivado/run_tb_trap.tcl
# ============================================================================
set repo_dir [file normalize [file dirname [info script]]/..]

set src_files [list \
    [file join $repo_dir src/basic_components/alu.v] \
    [file join $repo_dir src/basic_components/alu_control.v] \
    [file join $repo_dir src/basic_components/control.v] \
    [file join $repo_dir src/basic_components/decoder.v] \
    [file join $repo_dir src/basic_components/dmem.v] \
    [file join $repo_dir src/basic_components/imem.v] \
    [file join $repo_dir src/basic_components/imm_gen.v] \
    [file join $repo_dir src/basic_components/io_bus.v] \
    [file join $repo_dir src/basic_components/pc.v] \
    [file join $repo_dir src/basic_components/regfile.v] \
    [file join $repo_dir src/pipeline_cycle/branch_unit.v] \
    [file join $repo_dir src/pipeline_cycle/ex_mem_reg.v] \
    [file join $repo_dir src/pipeline_cycle/forwarding_unit.v] \
    [file join $repo_dir src/pipeline_cycle/hazard_unit.v] \
    [file join $repo_dir src/pipeline_cycle/id_ex_reg.v] \
    [file join $repo_dir src/pipeline_cycle/if_id_reg.v] \
    [file join $repo_dir src/pipeline_cycle/mem_wb_reg.v] \
    [file join $repo_dir src/pipeline_cycle/perf_counter.v] \
    [file join $repo_dir src/pipeline_cycle/pipeline_cpu_top.v] \
    [file join $repo_dir src/extension_components/div_unit.v] \
    [file join $repo_dir src/extension_components/trap_csr_unit.v] \
]

puts "============================================"
puts "  RISC-V 中断系统仿真"
puts "============================================"

create_project -in_memory -part xc7a100tfgg484-1
set_property include_dirs [file join $repo_dir src/basic_components] [get_filesets sources_1]
add_files -norecurse -fileset sources_1 {*}$src_files
add_files -fileset sim_1 [file join $repo_dir tb/tb_trap.v]
set_property SOURCE_SET sources_1 [get_filesets sim_1]
set_property TOP tb_trap [get_filesets sim_1]
set_property -name xsim.elaborate.xelab.more_options -value {--timescale 1ns/1ps} -objects [get_filesets sim_1]
update_compile_order -fileset sim_1

puts "Starting simulation..."
launch_simulation -simset sim_1 -mode behavioral
run all

puts ""
puts "Simulation complete."
close_sim
close_project -delete
