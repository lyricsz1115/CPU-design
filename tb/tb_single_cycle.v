`timescale 1ns/1ps

module tb_single_cycle;
    reg clk;
    reg rst;
    wire [31:0] debug_pc;
    wire [31:0] debug_dmem0;
    wire external_mem_read;
    wire external_mem_write;
    wire [31:0] external_addr;
    wire [31:0] external_write_data;
    wire inst_valid;

    cpu_top #(.INIT_FILE("sum.mem")) dut(
        .clk(clk),
        .rst(rst),
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

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst = 1'b1;
        #20;
        rst = 1'b0;
        repeat (80) @(posedge clk);

        if (debug_dmem0 !== 32'd55) begin
            $display("FAIL: single-cycle sum expected dmem[0]=55, got %0d", debug_dmem0);
            $finish;
        end

        $display("PASS: single-cycle sum dmem[0]=%0d", debug_dmem0);
        $finish;
    end
endmodule
