`timescale 1ns/1ps

// ============================================================================
// tb_mul_div — M-extension + RV32I 指令补全验证
// 覆盖：MUL, DIV, REM, ANDI, SLLI, ORI + 向后兼容
// ============================================================================

module tb_mul_div;
    reg clk;
    reg rst;

    // ── 流水线 CPU: mul_div 程序 ──
    wire               pipe_stall;
    wire               pipe_flush;
    wire               pipe_valid;
    wire [31:0]        pipe_cycle;
    wire [31:0]        pipe_instret;
    wire [31:0]        pipe_stall_cnt;
    wire [31:0]        pipe_flush_cnt;
    wire [31:0]        pipe_pc;
    wire [31:0]        pipe_dmem0;
    wire [31:0]        pipe_dmem1;
    wire [31:0]        pipe_dmem_data;
    wire [31:0]        pipe_imem_data;
    wire [31:0]        pipe_reg_data;

    // ── 流水线 CPU: branch 程序（回归，验证新分支单元不影响旧程序）──
    wire               br_stall;
    wire               br_flush;
    wire               br_valid;
    wire [31:0]        br_cycle;
    wire [31:0]        br_instret;
    wire [31:0]        br_stall_cnt;
    wire [31:0]        br_flush_cnt;
    wire [31:0]        br_pc;
    wire [31:0]        br_dmem0;
    wire [31:0]        br_dmem1;
    wire [31:0]        br_dmem_data;
    wire [31:0]        br_imem_data;
    wire [31:0]        br_reg_data;

    // ── 单周期 CPU: mul_div 程序（单周期 fallback 路径）──
    wire [31:0]        sc_pc;
    wire [31:0]        sc_dmem0;
    wire               sc_mem_read;
    wire               sc_mem_write;
    wire [31:0]        sc_addr;
    wire [31:0]        sc_wdata;
    wire               sc_valid;

    // ══════════════════════════════════════════════════════════════════
    // DUT 实例化
    // ══════════════════════════════════════════════════════════════════

    pipeline_cpu_top #(
        .INIT_FILE("mul_div.mem"),
        .USE_INIT_FILE(0),
        .PROGRAM_ID(7)
    ) dut_pipe (
        .clk(clk),
        .rst(rst),
        .imem_write_enable(1'b0),
        .imem_write_addr(32'b0),
        .imem_write_data(32'b0),
        .debug_imem_index(8'b0),
        .debug_dmem_index(8'b0),
        .debug_reg_index(5'b0),
        .external_read_data(32'b0),
        .external_mem_read(),
        .external_mem_write(),
        .external_addr(),
        .external_write_data(),
        .stall_debug(pipe_stall),
        .flush_debug(pipe_flush),
        .predict_taken_debug(),
        .inst_valid_debug(pipe_valid),
        .debug_cycle_count(pipe_cycle),
        .debug_instret_count(pipe_instret),
        .debug_stall_count(pipe_stall_cnt),
        .debug_flush_count(pipe_flush_cnt),
        .debug_cache_access_count(),
        .debug_cache_hit_count(),
        .debug_cache_miss_count(),
        .debug_pc(pipe_pc),
        .debug_dmem0(pipe_dmem0),
        .debug_dmem1(pipe_dmem1),
        .debug_dmem_data(pipe_dmem_data),
        .debug_imem_data(pipe_imem_data),
        .debug_reg_data(pipe_reg_data),
        .mtimecmp_mmio_write(1'b0),
        .mtimecmp_mmio_wdata(32'b0),
        .mtime_mmio_val(),
        .mtimecmp_mmio_val(),
        .irq_external(1'b0),
        .debug_stall(1'b0),
        .trap_taken_out()
    );

    pipeline_cpu_top #(
        .INIT_FILE("branch.mem"),
        .USE_INIT_FILE(0),
        .PROGRAM_ID(5)
    ) dut_branch (
        .clk(clk),
        .rst(rst),
        .imem_write_enable(1'b0),
        .imem_write_addr(32'b0),
        .imem_write_data(32'b0),
        .debug_imem_index(8'b0),
        .debug_dmem_index(8'b0),
        .debug_reg_index(5'b0),
        .external_read_data(32'b0),
        .external_mem_read(),
        .external_mem_write(),
        .external_addr(),
        .external_write_data(),
        .stall_debug(br_stall),
        .flush_debug(br_flush),
        .predict_taken_debug(),
        .inst_valid_debug(br_valid),
        .debug_cycle_count(br_cycle),
        .debug_instret_count(br_instret),
        .debug_stall_count(br_stall_cnt),
        .debug_flush_count(br_flush_cnt),
        .debug_cache_access_count(),
        .debug_cache_hit_count(),
        .debug_cache_miss_count(),
        .debug_pc(br_pc),
        .debug_dmem0(br_dmem0),
        .debug_dmem1(br_dmem1),
        .debug_dmem_data(br_dmem_data),
        .debug_imem_data(br_imem_data),
        .debug_reg_data(br_reg_data),
        .mtimecmp_mmio_write(1'b0),
        .mtimecmp_mmio_wdata(32'b0),
        .mtime_mmio_val(),
        .mtimecmp_mmio_val(),
        .irq_external(1'b0),
        .debug_stall(1'b0),
        .trap_taken_out()
    );

    cpu_top #(
        .INIT_FILE("mul_div.mem"),
        .USE_INIT_FILE(0),
        .PROGRAM_ID(7)
    ) dut_sc (
        .clk(clk),
        .rst(rst),
        .imem_write_enable(1'b0),
        .imem_write_addr(32'b0),
        .imem_write_data(32'b0),
        .external_read_data(32'b0),
        .external_mem_read(sc_mem_read),
        .external_mem_write(sc_mem_write),
        .external_addr(sc_addr),
        .external_write_data(sc_wdata),
        .inst_valid(sc_valid),
        .debug_pc(sc_pc),
        .debug_dmem0(sc_dmem0)
    );

    // ══════════════════════════════════════════════════════════════════
    // 时钟生成
    // ══════════════════════════════════════════════════════════════════

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ══════════════════════════════════════════════════════════════════
    // 测试主流程
    // ══════════════════════════════════════════════════════════════════

    integer failures;

    initial begin
        failures = 0;
        rst = 1'b1;
        #20;
        rst = 1'b0;

        // 除法需要 ~40 周期，整体程序约 15 条指令
        // 流水线需要足够周期让 div 完成 (32 迭代 + 前后各几拍)
        repeat (120) @(posedge clk);

        // ─── 流水线 CPU: M-extension 检查 ───
        $display("═══════════════════════════════════════════");
        $display("  Pipeline CPU — M-extension tests");
        $display("═══════════════════════════════════════════");

        check("MUL   20*3           ", pipe_dmem0, 32'd60);
        check("DIV   20/3           ", pipe_dmem1, 32'd6);
        check("REM   20%3           ", dut_pipe.u_dmem.mem[2], 32'd2);
        check("ANDI  20&0xFF        ", dut_pipe.u_dmem.mem[3], 32'd20);
        check("SLLI  3<<4           ", dut_pipe.u_dmem.mem[4], 32'd48);
        check("ORI   48|8           ", dut_pipe.u_dmem.mem[5], 32'd56);

        // ─── 流水线 CPU: 回归测试 ───
        $display("═══════════════════════════════════════════");
        $display("  Pipeline CPU — regression tests");
        $display("═══════════════════════════════════════════");

        check("Branch BEQ (regress)", br_dmem0, 32'd7);

        // ─── 单周期 CPU: I-type 修复验证 ───
        // 单周期 CPU 的乘法走 alu.v operator *
        // 除法走 alu.v 的 / 和 % (单周期 fallback)
        // ANDI/SLLI/ORI 走 alu_ctrl 的 I-type 路径
        $display("═══════════════════════════════════════════");
        $display("  Single-cycle CPU — I-type fix tests");
        $display("═══════════════════════════════════════════");

        check("SC MUL  20*3         ", sc_dmem0, 32'd60);
        // 单周期除法走 alu.v 内部 fallback，功能正确但时序差
        check("SC ANDI 20&0xFF      ", dut_sc.u_dmem.mem[3], 32'd20);
        check("SC SLLI 3<<4         ", dut_sc.u_dmem.mem[4], 32'd48);
        check("SC ORI  48|8         ", dut_sc.u_dmem.mem[5], 32'd56);

        // ─── 结果汇总 ───
        $display("═══════════════════════════════════════════");
        if (failures == 0) begin
            $display("  PASS: All M-extension + I-type fix tests passed");
        end else begin
            $display("  FAIL: %0d test(s) failed", failures);
        end
        $display("═══════════════════════════════════════════");

        $display("PERF mul_div: cycle=%0d instret=%0d stall=%0d flush=%0d",
            pipe_cycle, pipe_instret, pipe_stall_cnt, pipe_flush_cnt);

        $finish;
    end

    // ══════════════════════════════════════════════════════════════════
    // 辅助 task
    // ══════════════════════════════════════════════════════════════════

    task check;
        input [256*8-1:0] name;
        input [31:0] actual;
        input [31:0] expected;
        begin
            if (actual !== expected) begin
                $display("  FAIL: %s  expected=%0d  got=%0d", name, expected, actual);
                failures = failures + 1;
            end else begin
                $display("  OK:   %s  = %0d", name, actual);
            end
        end
    endtask

endmodule
