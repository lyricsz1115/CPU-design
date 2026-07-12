`timescale 1ns/1ps

module cached_pipeline_minisys_top #(
    parameter PROGRAM_ID = 8
)(
    input wire clk,
    input wire rst_btn,
    input wire [7:0] sw,
    output reg [7:0] led
);
    wire bus_mem_read;
    wire bus_mem_write;
    wire [31:0] bus_addr;
    wire [31:0] bus_write_data;
    wire [31:0] bus_read_data;
    wire [31:0] bus_debug_dmem0;
    wire [7:0] bus_led;

    wire stall_debug;
    wire flush_debug;
    wire predict_taken_debug;
    wire inst_valid_debug;
    wire [31:0] debug_cycle_count;
    wire [31:0] debug_instret_count;
    wire [31:0] debug_stall_count;
    wire [31:0] debug_flush_count;
    wire [31:0] debug_cache_access_count;
    wire [31:0] debug_cache_hit_count;
    wire [31:0] debug_cache_miss_count;
    wire [31:0] debug_pc;
    wire [31:0] cpu_debug_dmem0;
    wire [31:0] cpu_debug_dmem1;
    wire [31:0] cpu_debug_dmem_data;
    wire [31:0] debug_imem_data;
    wire [31:0] debug_reg_data;

    pipeline_cpu_top #(
        .INIT_FILE("cache_board_demo.mem"),
        .USE_INIT_FILE(0),
        .PROGRAM_ID(PROGRAM_ID),
        .ENABLE_IMEM_WRITE(0),
        .USE_EXTERNAL_DATA_BUS(1),
        .ENABLE_DATA_CACHE(1),
        .CACHE_NUM_SETS(8),
        .CACHE_WORDS_PER_LINE(4)
    ) u_cpu (
        .clk(clk),
        .rst(rst_btn),
        .imem_write_enable(1'b0),
        .imem_write_addr(32'b0),
        .imem_write_data(32'b0),
        .debug_imem_index(sw),
        .debug_dmem_index(sw),
        .debug_reg_index(sw[4:0]),
        .external_read_data(bus_read_data),
        .external_mem_read(bus_mem_read),
        .external_mem_write(bus_mem_write),
        .external_addr(bus_addr),
        .external_write_data(bus_write_data),
        .stall_debug(stall_debug),
        .flush_debug(flush_debug),
        .predict_taken_debug(predict_taken_debug),
        .inst_valid_debug(inst_valid_debug),
        .debug_cycle_count(debug_cycle_count),
        .debug_instret_count(debug_instret_count),
        .debug_stall_count(debug_stall_count),
        .debug_flush_count(debug_flush_count),
        .debug_cache_access_count(debug_cache_access_count),
        .debug_cache_hit_count(debug_cache_hit_count),
        .debug_cache_miss_count(debug_cache_miss_count),
        .debug_pc(debug_pc),
        .debug_dmem0(cpu_debug_dmem0),
        .debug_dmem1(cpu_debug_dmem1),
        .debug_dmem_data(cpu_debug_dmem_data),
        .debug_imem_data(debug_imem_data),
        .debug_reg_data(debug_reg_data),
        .mtimecmp_mmio_write(1'b0),
        .mtimecmp_mmio_wdata(32'b0),
        .mtime_mmio_val(),
        .mtimecmp_mmio_val(),
        .irq_external(1'b0)
    );

    io_bus u_io_bus (
        .clk(clk),
        .rst(rst_btn),
        .mem_read(bus_mem_read),
        .mem_write(bus_mem_write),
        .addr(bus_addr),
        .write_data(bus_write_data),
        .sw(sw),
        .cycle_count(debug_cycle_count),
        .instret_count(debug_instret_count),
        .stall_count(debug_stall_count),
        .flush_count(debug_flush_count),
        .debug_index(sw),
        .read_data(bus_read_data),
        .debug_dmem0(bus_debug_dmem0),
        .debug_data(),
        .led(bus_led),
        .mtimecmp_write(),
        .mtimecmp_wdata(),
        .mtime_val(32'b0),
        .mtimecmp_val(32'b0),
        .irq_external(1'b0)
    );

    always @(*) begin
        case (sw[7:6])
            2'b00: led = bus_led;
            2'b01: led = debug_cache_access_count[7:0];
            2'b10: led = debug_cache_hit_count[7:0];
            2'b11: led = debug_cache_miss_count[7:0];
            default: led = 8'b0;
        endcase
    end
endmodule
