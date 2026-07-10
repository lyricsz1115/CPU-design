module editable_minisys_top #(
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
    wire [31:0] debug_pc;
    wire [31:0] debug_dmem0;
    wire external_mem_read;
    wire external_mem_write;
    wire [31:0] external_addr;
    wire [31:0] external_write_data;
    wire inst_valid;
    reg [24:0] blink_count;

    wire cpu_rst = rst_btn | ~run_mode;
    wire [7:0] load_addr_display = {instr_index[3:0], byte_index, 2'b00};
    wire [7:0] load_display = blink_count[24] ? sw : load_addr_display;

    instr_loader #(
        .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)
    ) u_loader(
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

    cpu_top #(.INIT_FILE("sum.mem"), .USE_INIT_FILE(0), .PROGRAM_ID(0)) u_cpu(
        .clk(clk),
        .rst(cpu_rst),
        .imem_write_enable(imem_write_enable),
        .imem_write_addr(imem_write_addr),
        .imem_write_data(imem_write_data),
        .external_read_data(32'b0),
        .external_mem_read(external_mem_read),
        .external_mem_write(external_mem_write),
        .external_addr(external_addr),
        .external_write_data(external_write_data),
        .inst_valid(inst_valid),
        .debug_pc(debug_pc),
        .debug_dmem0(debug_dmem0)
    );

    always @(posedge clk or posedge rst_btn) begin
        if (rst_btn) begin
            blink_count <= 25'b0;
        end else begin
            blink_count <= blink_count + 25'd1;
        end
    end

    assign led = run_mode ? ((debug_dmem0[7:0] != 8'b0) ? debug_dmem0[7:0] : {1'b1, debug_pc[6:0]}) : load_display;
endmodule
