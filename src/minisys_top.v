module minisys_top(
    input wire clk,
    input wire rst_btn,
    output wire [7:0] led
);
    wire [31:0] debug_pc;
    wire [31:0] debug_dmem0;

    cpu_top #(.INIT_FILE("sum.mem")) u_cpu(
        .clk(clk),
        .rst(rst_btn),
        .debug_pc(debug_pc),
        .debug_dmem0(debug_dmem0)
    );

    assign led = debug_dmem0[7:0];
endmodule
