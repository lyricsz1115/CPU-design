`timescale 1ns/1ps

module tb_cached_pipeline;
    reg clk;
    reg rst;
    reg [7:0] sw;
    wire [7:0] led;

    wire mul_bus_mem_read;
    wire mul_bus_mem_write;
    wire [31:0] mul_bus_addr;
    wire [31:0] mul_bus_write_data;
    wire [31:0] mul_bus_read_data;
    wire [31:0] mul_bus_debug_dmem0;
    wire [7:0] mul_bus_led;
    wire [31:0] mul_cycle_count;
    wire [31:0] mul_instret_count;
    wire [31:0] mul_stall_count;
    wire [31:0] mul_flush_count;
    wire [31:0] mul_cache_access_count;
    wire [31:0] mul_cache_hit_count;
    wire [31:0] mul_cache_miss_count;
    wire [31:0] mul_pc;
    wire [31:0] mul_internal_dmem0;
    wire [31:0] mul_internal_dmem1;
    wire [31:0] mul_internal_dmem_data;
    wire [31:0] mul_debug_imem_data;
    wire [31:0] mul_debug_reg_data;

    cached_pipeline_minisys_top u_board_demo (
        .clk(clk),
        .rst_btn(rst),
        .sw(sw),
        .led(led)
    );

    pipeline_cpu_top #(
        .INIT_FILE("mul_div.mem"),
        .USE_INIT_FILE(0),
        .PROGRAM_ID(7),
        .USE_EXTERNAL_DATA_BUS(1),
        .ENABLE_DATA_CACHE(1)
    ) u_mul_cache_cpu (
        .clk(clk),
        .rst(rst),
        .imem_write_enable(1'b0),
        .imem_write_addr(32'b0),
        .imem_write_data(32'b0),
        .debug_imem_index(8'b0),
        .debug_dmem_index(8'b0),
        .debug_reg_index(5'b0),
        .external_read_data(mul_bus_read_data),
        .external_mem_read(mul_bus_mem_read),
        .external_mem_write(mul_bus_mem_write),
        .external_addr(mul_bus_addr),
        .external_write_data(mul_bus_write_data),
        .debug_cycle_count(mul_cycle_count),
        .debug_instret_count(mul_instret_count),
        .debug_stall_count(mul_stall_count),
        .debug_flush_count(mul_flush_count),
        .debug_cache_access_count(mul_cache_access_count),
        .debug_cache_hit_count(mul_cache_hit_count),
        .debug_cache_miss_count(mul_cache_miss_count),
        .debug_pc(mul_pc),
        .debug_dmem0(mul_internal_dmem0),
        .debug_dmem1(mul_internal_dmem1),
        .debug_dmem_data(mul_internal_dmem_data),
        .debug_imem_data(mul_debug_imem_data),
        .debug_reg_data(mul_debug_reg_data),
        .mtimecmp_mmio_write(1'b0),
        .mtimecmp_mmio_wdata(32'b0),
        .mtime_mmio_val(),
        .mtimecmp_mmio_val(),
        .irq_external(1'b0),
        .debug_stall(1'b0),
        .trap_taken_out()
    );

    io_bus u_mul_io_bus (
        .clk(clk),
        .rst(rst),
        .mem_read(mul_bus_mem_read),
        .mem_write(mul_bus_mem_write),
        .addr(mul_bus_addr),
        .write_data(mul_bus_write_data),
        .sw(8'b0),
        .cycle_count(mul_cycle_count),
        .instret_count(mul_instret_count),
        .stall_count(mul_stall_count),
        .flush_count(mul_flush_count),
        .debug_index(8'b0),
        .read_data(mul_bus_read_data),
        .debug_dmem0(mul_bus_debug_dmem0),
        .debug_data(),
        .led(mul_bus_led),
        .mtimecmp_write(),
        .mtimecmp_wdata(),
        .mtime_val(32'b0),
        .mtimecmp_val(32'b0),
        .irq_external(1'b0)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task check_value;
        input [255:0] name;
        input [31:0] actual;
        input [31:0] expected;
        begin
            if (actual !== expected) begin
                $display("FAIL: %s expected=%0d got=%0d", name, expected, actual);
                $finish;
            end
        end
    endtask

    initial begin
        rst = 1'b1;
        sw = 8'b0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        repeat (500) @(posedge clk);

        check_value("cache demo mem[0]", u_board_demo.u_cpu.u_dmem.mem[0], 32'h55);
        check_value("MMIO LED bypass", u_board_demo.u_io_bus.led_reg, 32'h55);
        check_value("cache demo access", u_board_demo.debug_cache_access_count, 32'd6);
        check_value("cache demo hit", u_board_demo.debug_cache_hit_count, 32'd4);
        check_value("cache demo miss", u_board_demo.debug_cache_miss_count, 32'd2);

        sw = 8'b00_000000;
        #1;
        if (led !== 8'h55) begin
            $display("FAIL: board result LED expected 0x55 got 0x%02h", led);
            $finish;
        end
        sw = 8'b01_000000;
        #1;
        if (led !== 8'd6) begin
            $display("FAIL: board access LED expected 6 got %0d", led);
            $finish;
        end
        sw = 8'b10_000000;
        #1;
        if (led !== 8'd4) begin
            $display("FAIL: board hit LED expected 4 got %0d", led);
            $finish;
        end
        sw = 8'b11_000000;
        #1;
        if (led !== 8'd2) begin
            $display("FAIL: board miss LED expected 2 got %0d", led);
            $finish;
        end

        check_value("cached MUL", u_mul_cache_cpu.u_dmem.mem[0], 32'd60);
        check_value("cached DIV", u_mul_cache_cpu.u_dmem.mem[1], 32'd6);
        check_value("cached REM", u_mul_cache_cpu.u_dmem.mem[2], 32'd2);
        check_value("cached ANDI", u_mul_cache_cpu.u_dmem.mem[3], 32'd20);
        check_value("cached SLLI", u_mul_cache_cpu.u_dmem.mem[4], 32'd48);
        check_value("cached ORI", u_mul_cache_cpu.u_dmem.mem[5], 32'd56);
        check_value("mul cache access", mul_cache_access_count, 32'd6);
        check_value("mul cache hit", mul_cache_hit_count, 32'd0);
        check_value("mul cache miss", mul_cache_miss_count, 32'd6);

        $display("PASS: cached pipeline, MMIO backing bus, LED views and MUL/DIV coexistence passed");
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL: cached pipeline test timed out");
        $finish;
    end
endmodule
