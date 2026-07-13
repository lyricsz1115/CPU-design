// ============================================================================
// tb_trap.v — RISC-V 中断系统综合测试
// ============================================================================
// 测试覆盖:
//   T1. 定时器中断触发 (mtimecmp=80, 约 80 周期后触发)
//   T2. 影子寄存器保存 — ISR 中回读寄存器初值 → dmem[1..5]
//   T3. 影子寄存器恢复 — MRET 后寄存器恢复 → regfile regs[1,5,6,7]
//   T4. 非影子寄存器 — x8(s0) 不被恢复, 保留 ISR 修改值 0xFE
//
// 预期 (350 周期后):
//   dmem[0] = 0xFF         ISR 标记
//   dmem[1] = 0xA1         影子 x1(ra) 保存值
//   dmem[2] = 0xB5         影子 x5(t0) 保存值
//   dmem[3] = 0xC6         影子 x6(t1) 保存值
//   dmem[4] = 0xD7         影子 x7(t2) 保存值
//   dmem[5] = 0xE8         x8(s0) 保存值 (对照: 非影子寄存器)
//   regs[1] = 0xA1         MRET 后 x1 恢复
//   regs[5] = 0xB5         MRET 后 x5 恢复
//   regs[6] = 0xC6         MRET 后 x6 恢复
//   regs[7] = 0xD7         MRET 后 x7 恢复
//   regs[8] = 0xFE         MRET 后 x8 保持 ISR 修改值 (不被恢复!)
// ============================================================================

`timescale 1ns/1ps

module tb_trap;
    reg clk;
    reg rst;

    // ── Pipeline CPU 调试信号 ──
    wire               pipe_stall;
    wire               pipe_flush;
    wire               pipe_predict;
    wire               pipe_valid;
    wire [31:0]        pipe_cycle_count;
    wire [31:0]        pipe_instret_count;
    wire [31:0]        pipe_stall_count;
    wire [31:0]        pipe_flush_count;
    wire [31:0]        pipe_pc;
    wire [31:0]        pipe_dmem0;
    wire [31:0]        pipe_dmem1;
    wire [31:0]        pipe_dmem_data;
    wire [31:0]        pipe_imem_data;
    wire [31:0]        pipe_reg_data;

    // ── 总线接口 ──
    wire        bus_mem_read;
    wire        bus_mem_write;
    wire [31:0] bus_addr;
    wire [31:0] bus_write_data;
    wire [31:0] bus_read_data;

    // ── 定时器 MMIO ──
    wire        mtimecmp_mmio_write;
    wire [31:0] mtimecmp_mmio_wdata;
    wire [31:0] mtime_mmio_val;
    wire [31:0] mtimecmp_mmio_val;

    // ═══════════════════════════════════════════════════════
    // DUT: 流水线 CPU + io_bus (MMIO 路由)
    // ═══════════════════════════════════════════════════════

    pipeline_cpu_top #(
        .INIT_FILE("trap_test.mem"),
        .USE_INIT_FILE(1),
        .PROGRAM_ID(0),
        .USE_EXTERNAL_DATA_BUS(1)
    ) dut (
        .clk(clk),
        .rst(rst),
        .imem_write_enable(1'b0),
        .imem_write_addr(32'b0),
        .imem_write_data(32'b0),
        .debug_imem_index(8'b0),
        .debug_dmem_index(8'b0),
        .debug_reg_index(5'b0),
        .external_read_data(bus_read_data),
        .external_mem_read(bus_mem_read),
        .external_mem_write(bus_mem_write),
        .external_addr(bus_addr),
        .external_write_data(bus_write_data),
        .mtimecmp_mmio_write(mtimecmp_mmio_write),
        .mtimecmp_mmio_wdata(mtimecmp_mmio_wdata),
        .mtime_mmio_val(mtime_mmio_val),
        .mtimecmp_mmio_val(mtimecmp_mmio_val),
        .irq_external(1'b0),
        .irq_external_ack(),
        .debug_stall(1'b0),
        .trap_taken_out(),
        .stall_debug(pipe_stall),
        .flush_debug(pipe_flush),
        .predict_taken_debug(pipe_predict),
        .inst_valid_debug(pipe_valid),
        .debug_cycle_count(pipe_cycle_count),
        .debug_instret_count(pipe_instret_count),
        .debug_stall_count(pipe_stall_count),
        .debug_flush_count(pipe_flush_count),
        .debug_cache_access_count(),
        .debug_cache_hit_count(),
        .debug_cache_miss_count(),
        .debug_pc(pipe_pc),
        .debug_dmem0(pipe_dmem0),
        .debug_dmem1(pipe_dmem1),
        .debug_dmem_data(pipe_dmem_data),
        .debug_imem_data(pipe_imem_data),
        .debug_reg_data(pipe_reg_data)
    );

    // ═══════════════════════════════════════════════════════
    // io_bus — MMIO: mtime/mtimecmp (0x1000xxxx)
    // ═══════════════════════════════════════════════════════
    io_bus u_io_bus (
        .clk(clk),
        .rst(rst),
        .mem_read(bus_mem_read),
        .mem_write(bus_mem_write),
        .addr(bus_addr),
        .write_data(bus_write_data),
        .sw(8'b0),
        .cycle_count(pipe_cycle_count),
        .instret_count(pipe_instret_count),
        .stall_count(pipe_stall_count),
        .flush_count(pipe_flush_count),
        .debug_index(8'b0),
        .read_data(bus_read_data),
        .debug_dmem0(),
        .debug_data(),
        .led(),
        .mtimecmp_write(mtimecmp_mmio_write),
        .mtimecmp_wdata(mtimecmp_mmio_wdata),
        .mtime_val(mtime_mmio_val),
        .mtimecmp_val(mtimecmp_mmio_val),
        .irq_external(1'b0)
    );

    // ═══════════════════════════════════════════════════════
    // 时钟生成 (100 MHz, 10 ns 周期)
    // ═══════════════════════════════════════════════════════
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ═══════════════════════════════════════════════════════
    // 测试流程
    // ═══════════════════════════════════════════════════════
    integer failures;

    // ── 辅助 task: 检查 dmem ──
    task check_dmem;
        input [7:0] index;
        input [31:0] expected;
        input [256*8-1:0] name;
        begin
            if (dut.u_dmem.mem[index] !== expected) begin
                $display("  FAIL: dmem[%0d] (%0s) = %h (expected %h)",
                    index, name, dut.u_dmem.mem[index], expected);
                failures = failures + 1;
            end else begin
                $display("  PASS: dmem[%0d] (%0s) = %h", index, name, expected);
            end
        end
    endtask

    // ── 辅助 task: 检查 regfile ──
    task check_reg;
        input [4:0] index;
        input [31:0] expected;
        input [256*8-1:0] name;
        begin
            if (dut.u_regfile.regs[index] !== expected) begin
                $display("  FAIL: regs[%0d] (%0s) = %h (expected %h)",
                    index, name, dut.u_regfile.regs[index], expected);
                failures = failures + 1;
            end else begin
                $display("  PASS: regs[%0d] (%0s) = %h", index, name, expected);
            end
        end
    endtask

    initial begin
        failures = 0;

        // ── 复位 ──
        rst = 1'b1;
        #20;
        rst = 1'b0;

        // ── 运行 350 周期 ──
        //    约 80 周期 → mtime 到达 mtimecmp=80 → 定时器中断
        //    ~100 周期 → 流水线冲刷 + ISR 执行 + MRET 返回
        //    剩余 ~170 周期 → 主循环继续，确保状态稳定
        repeat (350) @(posedge clk);

        // ═══════════════════════════════════════════════════
        // 结果报告
        // ═══════════════════════════════════════════════════
        $display("==============================================");
        $display("  RISC-V 中断系统综合测试结果");
        $display("==============================================");
        $display("");

        // ── T1: ISR 标记 ──
        $display("── T1: 定时器中断触发 + ISR 执行 ──");
        check_dmem(0, 32'h000000FF, "ISR marker");

        $display("");
        $display("── T2: 影子寄存器保存 (ISR 中回读) ──");
        check_dmem(1, 32'h000000A1, "sh_ra (x1)");
        check_dmem(2, 32'h000000B5, "sh_t0 (x5)");
        check_dmem(3, 32'h000000C6, "sh_t1 (x6)");
        check_dmem(4, 32'h000000D7, "sh_t2 (x7)");
        check_dmem(5, 32'h000000E8, "x8/s0 (not shadowed)");

        $display("");
        $display("── T3: MRET 影子寄存器恢复 ──");
        check_reg(1, 32'h000000A1, "ra(x1) restored");
        check_reg(5, 32'h000000B5, "t0(x5) restored");
        check_reg(6, 32'h000000C6, "t1(x6) restored");
        check_reg(7, 32'h000000D7, "t2(x7) restored");

        $display("");
        $display("── T4: 非影子寄存器不被恢复 ──");
        check_reg(8, 32'h000000FE, "s0(x8) NOT restored");

        // ── 性能计数器 ──
        $display("");
        $display("── 性能计数器 ──");
        $display("  cycle=%0d instret=%0d stall=%0d flush=%0d",
            pipe_cycle_count, pipe_instret_count,
            pipe_stall_count, pipe_flush_count);

        // ── 最终汇总 ──
        $display("");
        if (failures == 0) begin
            $display("==============================================");
            $display("  PASS: 全部 10 项检查通过!");
            $display("==============================================");
        end else begin
            $display("==============================================");
            $display("  FAIL: %0d/10 项检查失败", failures);
            $display("==============================================");
        end

        $finish;
    end

endmodule
