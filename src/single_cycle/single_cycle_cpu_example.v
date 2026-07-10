module minisys_top(
    input wire clk,
    input wire rst_btn,
    output wire [7:0] led
);
    wire [31:0] debug_pc;
    wire [31:0] debug_dmem0;
    wire external_mem_read;
    wire external_mem_write;
    wire [31:0] external_addr;
    wire [31:0] external_write_data;
    wire inst_valid;

    cpu_top #(.INIT_FILE("sum.mem"), .USE_INIT_FILE(0), .PROGRAM_ID(0)) u_cpu(
        .clk(clk),
        .rst(rst_btn),
        .imem_write_enable(1'b0),
        .imem_write_addr(32'b0),
        .imem_write_data(32'b0),
        .external_read_data(32'b0),
        .external_mem_read(external_mem_read),
        .external_mem_write(external_mem_write),
        .external_addr(external_addr),
        .external_write_data(external_write_data),
        .inst_valid(inst_valid),
        .debug_pc(debug_pc),
        .debug_dmem0(debug_dmem0)
    );

    assign led = debug_dmem0[7:0];
endmodule
