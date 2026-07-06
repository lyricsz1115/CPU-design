`timescale 1ns/1ps

module tb_single_cycle;
    reg clk;
    reg rst;
    wire [31:0] debug_pc;
    wire [31:0] debug_dmem0;

    cpu_top #(.INIT_FILE("program/sum.mem")) dut(
        .clk(clk),
        .rst(rst),
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
