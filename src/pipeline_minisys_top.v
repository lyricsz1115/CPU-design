module pipeline_minisys_top(
    input wire clk,
    input wire rst_btn,
    output wire [7:0] led
);
    wire stall_debug;
    wire flush_debug;
    wire inst_valid_debug;
    wire [31:0] debug_cycle_count;
    wire [31:0] debug_instret_count;
    wire [31:0] debug_stall_count;
    wire [31:0] debug_flush_count;
    wire [31:0] debug_pc;
    wire [31:0] debug_dmem0;
    wire [31:0] debug_dmem1;

    pipeline_cpu_top #(.INIT_FILE("sum.mem"), .USE_INIT_FILE(0), .PROGRAM_ID(0)) u_cpu(
        .clk(clk),
        .rst(rst_btn),
        .stall_debug(stall_debug),
        .flush_debug(flush_debug),
        .inst_valid_debug(inst_valid_debug),
        .debug_cycle_count(debug_cycle_count),
        .debug_instret_count(debug_instret_count),
        .debug_stall_count(debug_stall_count),
        .debug_flush_count(debug_flush_count),
        .debug_pc(debug_pc),
        .debug_dmem0(debug_dmem0),
        .debug_dmem1(debug_dmem1)
    );

    assign led = debug_dmem0[7:0];
endmodule
