module system_top #(
    parameter INIT_FILE = "io_led.mem",
    parameter USE_INIT_FILE = 1,
    parameter PROGRAM_ID = 1
)(
    input wire clk,
    input wire rst,
    input wire [7:0] sw,
    output wire [7:0] led,
    output wire [31:0] debug_pc,
    output wire [31:0] debug_dmem0,
    output wire [31:0] debug_cycle_count,
    output wire [31:0] debug_instret_count
);
    wire [31:0] bus_read_data;
    wire bus_mem_read;
    wire bus_mem_write;
    wire [31:0] bus_addr;
    wire [31:0] bus_write_data;
    wire inst_valid;
    wire [31:0] cycle_count;
    wire [31:0] instret_count;
    wire [31:0] stall_count;
    wire [31:0] flush_count;

    cpu_top #(
        .INIT_FILE(INIT_FILE),
        .USE_INIT_FILE(USE_INIT_FILE),
        .PROGRAM_ID(PROGRAM_ID),
        .USE_EXTERNAL_DATA_BUS(1)
    ) u_cpu (
        .clk(clk),
        .rst(rst),
        .imem_write_enable(1'b0),
        .imem_write_addr(32'b0),
        .imem_write_data(32'b0),
        .external_read_data(bus_read_data),
        .external_mem_read(bus_mem_read),
        .external_mem_write(bus_mem_write),
        .external_addr(bus_addr),
        .external_write_data(bus_write_data),
        .inst_valid(inst_valid),
        .debug_pc(debug_pc),
        .debug_dmem0(debug_dmem0)
    );

    perf_counter u_perf_counter(
        .clk(clk),
        .rst(rst),
        .inst_valid(inst_valid),
        .stall(1'b0),
        .flush(1'b0),
        .cycle_count(cycle_count),
        .instret_count(instret_count),
        .stall_count(stall_count),
        .flush_count(flush_count)
    );

    io_bus u_io_bus(
        .clk(clk),
        .rst(rst),
        .mem_read(bus_mem_read),
        .mem_write(bus_mem_write),
        .addr(bus_addr),
        .write_data(bus_write_data),
        .sw(sw),
        .cycle_count(cycle_count),
        .instret_count(instret_count),
        .stall_count(stall_count),
        .flush_count(flush_count),
        .debug_index(sw),
        .read_data(bus_read_data),
        .debug_dmem0(),
        .debug_data(),
        .led(led)
    );

    assign debug_cycle_count = cycle_count;
    assign debug_instret_count = instret_count;
endmodule
