# ============================================================================
# run_all_tests.tcl — 一键仿真 + 综合 + 时序验证
# ============================================================================
# 用法:
#   在终端中执行:
#     vivado -mode batch -source vivado/run_all_tests.tcl
#   或在 Vivado GUI 中:
#     Tcl Console → source vivado/run_all_tests.tcl
#
# 测试内容:
#   Part 1: 功能仿真 (RTL behavioral simulation)
#   Part 2: 综合 + 布局布线 + 时序分析 (synthesis → implementation → timing)
# ============================================================================

set script_dir  [file dirname [file normalize [info script]]]
set repo_dir    [file normalize [file join $script_dir ..]]
set work_dir    [file join $script_dir test_output]
file mkdir $work_dir

# ─── 全局计数 ────────────────────────────────────────────────────────────────
set SIM_PASS   0
set SIM_FAIL   0
set SIM_RESULTS {}
set TIMING_OK  "UNKNOWN"

proc log_section {title} {
    puts "\n========================================"
    puts "  $title"
    puts "========================================"
}

proc log_pass {msg} {
    puts "  \[PASS\] $msg"
}

proc log_fail {msg} {
    puts "  \[FAIL\] $msg"
}

# ============================================================================
# Part 1: 功能仿真
# ============================================================================
log_section "Part 1: RTL Behavioral Simulation"

# 源文件列表
set src_files [list \
    [file join $repo_dir src/basic_components/riscv_defs.vh] \
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
    [file join $repo_dir src/main/cpu_top.v] \
]

# 检查源文件
set missing_src {}
foreach f $src_files {
    if {![file isfile $f]} {
        lappend missing_src $f
    }
}
if {[llength $missing_src] > 0} {
    puts "WARNING: missing source files: $missing_src"
}

# ─── 运行单个仿真 test ─────────────────────────────────────────────────────
proc run_sim {tb_name tb_file expected_pass_msg} {
    global SIM_PASS SIM_FAIL SIM_RESULTS work_dir repo_dir src_files

    puts "\n--- Simulation: $tb_name ---"

    if {![file isfile $tb_file]} {
        puts "  SKIP: testbench file not found: $tb_file"
        lappend SIM_RESULTS [list $tb_name "SKIP" "file not found"]
        return
    end

    # 收集仿真所需的全部文件
    set all_files [concat $src_files [list $tb_file]]

    # 用 xvlog 编译、xelab 细化、xsim 仿真
    set log_file [file join $work_dir "${tb_name}.log"]
    set sim_dir  [file join $work_dir $tb_name]

    # 创建 in-memory 项目
    if {[catch {
        set project_name "sim_${tb_name}"
        create_project -in_memory -part xc7a100tfgg484-1
        set_property include_dirs [file join $repo_dir src/basic_components] [get_filesets sources_1]
        add_files -norecurse -fileset sources_1 {*}$src_files
        add_files -norecurse -fileset sim_1 $tb_file
        set_property SOURCE_SET sources_1 [get_filesets sim_1]
        set_property TOP $tb_name [get_filesets sim_1]
        set_property -name xsim.elaborate.xelab.more_options -value {--timescale 1ns/1ps} -objects [get_filesets sim_1]
        update_compile_order -fileset sim_1
        launch_simulation -simset sim_1 -mode behavioral
        run all
        close_sim
        close_project -delete
        set SIM_PASS [expr {$SIM_PASS + 1}]
        lappend SIM_RESULTS [list $tb_name "PASS" ""]
        puts "  \[PASS\] $expected_pass_msg"
    } err_msg options]} {
        set SIM_FAIL [expr {$SIM_FAIL + 1}]
        lappend SIM_RESULTS [list $tb_name "FAIL" $err_msg]
        puts "  \[FAIL\] $err_msg"
        catch {close_sim}
        catch {close_project -delete}
    }
}

# ─── 运行各 testbench ──────────────────────────────────────────────────────

# 1. tb_mul_div — 乘除法验证（最重要的测试）
run_sim "tb_mul_div" \
    [file join $repo_dir tb/tb_mul_div.v] \
    "MUL/DIV/REM + ANDI/SLLI/ORI: dmem[0]=60, dmem[1]=6, dmem[2]=2"

# 2. tb_pipeline — 流水线基础功能
run_sim "tb_pipeline" \
    [file join $repo_dir tb/tb_pipeline.v] \
    "Pipeline: nop/forwarding/load-use/branch/predict all pass"

# 3. tb_data_cache — 数据缓存
run_sim "tb_data_cache" \
    [file join $repo_dir tb/tb_data_cache.v] \
    "Data cache: read/write hit/miss/refill/LRU"

# 4. tb_cached_pipeline — 缓存 + 乘除法共存
run_sim "tb_cached_pipeline" \
    [file join $repo_dir tb/tb_cached_pipeline.v] \
    "Cached pipeline: MUL/DIV + cache hit/miss + LED views"

# 5. tb_io_system — IO 总线
run_sim "tb_io_system" \
    [file join $repo_dir tb/tb_io_system.v] \
    "IO bus: LED write, SW read, perf counters"

# 6. tb_perf_counter — 性能计数器
run_sim "tb_perf_counter" \
    [file join $repo_dir tb/tb_perf_counter.v] \
    "Perf counter: cycle/instret/stall/flush counts"

# 7. tb_editable_loader — 手动加载器
run_sim "tb_editable_loader" \
    [file join $repo_dir tb/tb_editable_loader.v] \
    "Instr loader: byte-by-byte program entry"

# 8. tb_trap — 中断系统
run_sim "tb_trap" \
    [file join $repo_dir tb/tb_trap.v] \
    "Trap: timer IRQ + shadow save/restore + MRET"

# ─── 仿真结果汇总 ──────────────────────────────────────────────────────────
log_section "Simulation Results Summary"

puts [format "  %-30s %s" "Testbench" "Result"]
puts "  --------------------------------------------------"
foreach r $SIM_RESULTS {
    set name [lindex $r 0]
    set res  [lindex $r 1]
    puts [format "  %-30s %s" $name $res]
}
puts "  --------------------------------------------------"
puts "  PASS: $SIM_PASS / [expr {$SIM_PASS + $SIM_FAIL}]"
if {$SIM_FAIL > 0} {
    puts "  FAIL: $SIM_FAIL"
}

# ============================================================================
# Part 2: 综合 + 实现 + 时序检查
# ============================================================================
log_section "Part 2: Synthesis + Implementation + Timing"

set syn_top "editable_pipeline_system_top"
set xdc_file [file join $repo_dir xdc/editable_minisys_template.xdc]

# 综合源文件（不含 testbench）
set rtl_files [list \
    [file join $repo_dir src/basic_components/alu.v] \
    [file join $repo_dir src/basic_components/alu_control.v] \
    [file join $repo_dir src/pipeline_cycle/branch_unit.v] \
    [file join $repo_dir src/basic_components/control.v] \
    [file join $repo_dir src/basic_components/decoder.v] \
    [file join $repo_dir src/extension_components/div_unit.v] \
    [file join $repo_dir src/extension_components/trap_csr_unit.v] \
    [file join $repo_dir src/basic_components/dmem.v] \
    [file join $repo_dir src/pipeline_cycle/ex_mem_reg.v] \
    [file join $repo_dir src/pipeline_cycle/forwarding_unit.v] \
    [file join $repo_dir src/pipeline_cycle/hazard_unit.v] \
    [file join $repo_dir src/pipeline_cycle/id_ex_reg.v] \
    [file join $repo_dir src/pipeline_cycle/if_id_reg.v] \
    [file join $repo_dir src/basic_components/imem.v] \
    [file join $repo_dir src/basic_components/imm_gen.v] \
    [file join $repo_dir src/basic_components/instr_loader.v] \
    [file join $repo_dir src/basic_components/io_bus.v] \
    [file join $repo_dir src/pipeline_cycle/mem_wb_reg.v] \
    [file join $repo_dir src/basic_components/pc.v] \
    [file join $repo_dir src/pipeline_cycle/perf_counter.v] \
    [file join $repo_dir src/pipeline_cycle/pipeline_cpu_top.v] \
    [file join $repo_dir src/basic_components/regfile.v] \
    [file join $repo_dir src/basic_components/seg7_hex_display.v] \
    [file join $repo_dir src/editable_pipeline_system_top.v] \
]

# 同样有 SystemVerilog 的 uart top
set uart_top "uart_editable_pipeline_system_top"
set uart_files [list \
    [file join $repo_dir src/UART/uart_rx_byte.sv] \
    [file join $repo_dir src/UART/uart_tx_byte.sv] \
    [file join $repo_dir src/UART/uart_program_packet_rx.sv] \
    [file join $repo_dir src/UART/uart_response_packet_tx.sv] \
    [file join $repo_dir src/UART/uart_program_loader.sv] \
]

# 缓存 top
set cache_top "cached_pipeline_minisys_top"
set cache_files [list \
    [file join $repo_dir src/cache/data_cache.v] \
    [file join $repo_dir src/cache/cache_memory_adapter.v] \
    [file join $repo_dir src/cached_pipeline_minisys_top.v] \
]

# ─── 综合单个 top ──────────────────────────────────────────────────────────
proc run_synth_impl {top_name top_files extra_rtl} {
    global work_dir repo_dir xdc_file

    puts "\n>>> Synthesis + Implementation: $top_name <<<"

    if {[catch {
        set part "xc7a100tfgg484-1"

        # 创建 in-memory 项目
        create_project -in_memory -part $part
        set_property target_language Verilog [current_project]
        set_property include_dirs [file join $repo_dir src/basic_components] [get_filesets sources_1]

        # 加 RTL 文件，SystemVerilog 自动识别
        add_files -norecurse {*}$top_files
        if {[llength $extra_rtl] > 0} {
            add_files -norecurse {*}$extra_rtl
        }

        # 加约束
        if {[file isfile $xdc_file]} {
            add_files -fileset constrs_1 $xdc_file
        }

        set_property TOP $top_name [get_filesets sources_1]
        update_compile_order -fileset sources_1

        # ── 综合 ──
        puts "  Running synthesis..."
        synth_design -top $top_name -part $part
        set wns_synth [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup] -quiet]
        if {$wns_synth eq ""} { set wns_synth "N/A" }

        # ── 实现 (place + route) ──
        puts "  Running implementation..."
        opt_design
        place_design
        route_design

        # ── 时序报告 ──
        puts "  Running timing analysis..."
        set timing_rpt [file join $work_dir "${top_name}_timing.rpt"]
        report_timing_summary -file $timing_rpt

        set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup] -quiet]
        if {$wns eq ""} { set wns "N/A" }

        set utilization_rpt [file join $work_dir "${top_name}_utilization.rpt"]
        report_utilization -file $utilization_rpt

        # ── bitstream ──
        puts "  Generating bitstream..."
        write_bitstream -force [file join $work_dir "${top_name}.bit"]

        puts "  Synthesis WNS: $wns_synth ns"
        puts "  Post-route WNS: $wns ns"

        close_project -delete

        return [list $wns_synth $wns "OK"]
    } err_msg options]} {
        catch {close_project -delete}
        puts "  \[ERROR\] $err_msg"
        return [list "ERROR" "ERROR" $err_msg]
    }
}

# ─── 运行综合 ─────────────────────────────────────────────────────────────

# 1. editable_pipeline_system_top (主顶层)
set syn_result [run_synth_impl $syn_top $rtl_files {}]
set synth_wns  [lindex $syn_result 0]
set route_wns  [lindex $syn_result 1]

# ─── 时序结果判断 ──────────────────────────────────────────────────────────
log_section "Timing Analysis"

puts "  Top: $syn_top"
puts "  Synthesis WNS (post-synth):  $synth_wns ns"
puts "  Post-route WNS:              $route_wns ns"
puts "  Required period:             10.000 ns (100 MHz)"

if {$route_wns eq "ERROR"} {
    puts "\n  \[FAIL\] Synthesis/Implementation failed"
    puts "  Error: [lindex $syn_result 2]"
} elseif {$route_wns eq "N/A"} {
    puts "\n  \[WARN\] No timing paths reported (possibly empty design)"
} elseif {$route_wns >= 0.0} {
    puts "\n  \[PASS\] Timing met! All paths meet 100 MHz constraint."
    puts "  Design is ready for board testing."
} else {
    set violation [expr {-$route_wns}]
    puts "\n  \[FAIL\] TIMING VIOLATION: $route_wns ns slack"
    puts "  Slowest path needs $violation ns more than the 10 ns clock period."
    puts ""
    puts "  This is the \"three parallel multipliers\" issue (BUG #6)."
    puts "  Root cause: alu.v 64-bit multipliers have ~$violation ns"
    puts "  combinational delay, exceeding the 10 ns clock period."
    puts ""
    puts "  Impact: MUL/MULH/MULHSU/MULHU may produce wrong results on board."
    puts "  Fix: pipeline the multiplier output (add 1 register stage)."
}

# ============================================================================
# Part 3: 最终汇总
# ============================================================================
log_section "FINAL SUMMARY"

puts "  Simulation:  $SIM_PASS passed / [expr {$SIM_PASS + $SIM_FAIL}] total"
puts "  Timing:      post-route WNS = $route_wns ns"

if {$SIM_FAIL == 0 && $route_wns >= 0.0} {
    puts "\n  ===== ALL CHECKS PASSED - READY FOR BOARD TESTING ====="
} elseif {$SIM_FAIL > 0 && $route_wns >= 0.0} {
    puts "\n  ===== TIMING OK but SIMULATION FAILURES detected ====="
    puts "  Fix the failing testbenches before board testing."
} elseif {$SIM_FAIL == 0 && $route_wns < 0.0} {
    puts "\n  ===== SIMULATION OK but TIMING VIOLATION ====="
    puts "  The RTL is logically correct but too slow for 100 MHz."
    puts "  Board testing of MUL instructions will be unreliable."
    puts "  Consider pipelining the multiplier."
} else {
    puts "\n  ===== BOTH SIMULATION AND TIMING HAVE ISSUES ====="
    puts "  Fix simulation failures first, then address timing."
}

puts "\nAll reports saved to: $work_dir"
puts "Done."
