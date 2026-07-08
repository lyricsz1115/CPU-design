module system_minisys_top(
    input wire clk,
    input wire rst_btn,
    output wire [7:0] led
);
    wire [31:0] debug_pc;
    wire [31:0] debug_dmem0;
    wire [31:0] debug_cycle_count;
    wire [31:0] debug_instret_count;

    system_top #(.INIT_FILE("io_led.mem"), .USE_INIT_FILE(0), .PROGRAM_ID(1)) u_system(
        .clk(clk),
        .rst(rst_btn),
        .sw(8'b0),
        .led(led),
        .debug_pc(debug_pc),
        .debug_dmem0(debug_dmem0),
        .debug_cycle_count(debug_cycle_count),
        .debug_instret_count(debug_instret_count)
    );
endmodule
