module editable_pipeline_system_top #(
    parameter DEBOUNCE_CYCLES = 1000000
)(
    input wire clk,
    input wire rst_btn,
    input wire [7:0] sw,
    input wire btn_write,
    input wire btn_next,
    input wire btn_clear,
    input wire btn_run,
    output wire [7:0] led
);
    wire run_mode;
    wire imem_write_enable;
    wire [31:0] imem_write_addr;
    wire [31:0] imem_write_data;
    wire [7:0] instr_index;
    wire [1:0] byte_index;
    wire [31:0] current_word;

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

    wire bus_mem_read;
    wire bus_mem_write;
    wire [31:0] bus_addr;
    wire [31:0] bus_write_data;
    wire [31:0] bus_read_data;
    wire [31:0] bus_debug_dmem0;
    wire [7:0] bus_led;

    reg [24:0] blink_count;
    reg [7:0] run_display;

    wire cpu_rst = rst_btn | ~run_mode;
    wire [7:0] load_addr_display = {instr_index[3:0], byte_index, 2'b00};
    wire [7:0] load_display = blink_count[24] ? sw : load_addr_display;
    wire [7:0] result_display = (bus_led != 8'b0) ? bus_led : {1'b1, debug_pc[6:0]};

    instr_loader #(
        .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)
    ) u_loader (
        .clk(clk),
        .rst(rst_btn),
        .sw(sw),
        .btn_write(btn_write),
        .btn_next(btn_next),
        .btn_clear(btn_clear),
        .btn_run(btn_run),
        .run_mode(run_mode),
        .imem_write_enable(imem_write_enable),
        .imem_write_addr(imem_write_addr),
        .imem_write_data(imem_write_data),
        .instr_index(instr_index),
        .byte_index(byte_index),
        .current_word(current_word)
    );

    pipeline_cpu_top #(
        .INIT_FILE("sum.mem"),
        .USE_INIT_FILE(0),
        .PROGRAM_ID(0),
        .ENABLE_IMEM_WRITE(1),
        .USE_EXTERNAL_DATA_BUS(1),
        .ENABLE_DATA_CACHE(1),
        .CACHE_NUM_SETS(8),
        .CACHE_WORDS_PER_LINE(4)
    ) u_cpu (
        .clk(clk),
        .rst(cpu_rst),
        .imem_write_enable(imem_write_enable),
        .imem_write_addr(imem_write_addr),
        .imem_write_data(imem_write_data),
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
        .rst(cpu_rst),
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

    always @(posedge clk or posedge rst_btn) begin
        if (rst_btn) begin
            blink_count <= 25'b0;
        end else begin
            blink_count <= blink_count + 25'd1;
        end
    end

    always @(*) begin
        case (sw[7:6])
            2'b00: run_display = result_display;
            2'b01: run_display = debug_cache_access_count[7:0];
            2'b10: run_display = debug_cache_hit_count[7:0];
            2'b11: run_display = debug_cache_miss_count[7:0];
            default: run_display = result_display;
        endcase
    end

    assign led = run_mode ? run_display : load_display;
endmodule
