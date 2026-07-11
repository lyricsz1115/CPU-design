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
        .debug_dmem1(cpu_debug_dmem1)
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
        .read_data(bus_read_data),
        .debug_dmem0(bus_debug_dmem0),
        .led(bus_led)
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
