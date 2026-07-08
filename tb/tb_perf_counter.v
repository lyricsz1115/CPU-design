`timescale 1ns/1ps

module tb_perf_counter;
    reg clk;
    reg rst;
    reg inst_valid;
    reg stall;
    reg flush;
    wire [31:0] cycle_count;
    wire [31:0] instret_count;
    wire [31:0] stall_count;
    wire [31:0] flush_count;

    perf_counter dut(
        .clk(clk),
        .rst(rst),
        .inst_valid(inst_valid),
        .stall(stall),
        .flush(flush),
        .cycle_count(cycle_count),
        .instret_count(instret_count),
        .stall_count(stall_count),
        .flush_count(flush_count)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst = 1'b1;
        inst_valid = 1'b0;
        stall = 1'b0;
        flush = 1'b0;
        #12;
        rst = 1'b0;
        inst_valid = 1'b1;
        stall = 1'b0;
        flush = 1'b0;

        @(negedge clk);
        inst_valid = 1'b1;
        stall = 1'b1;
        flush = 1'b0;

        @(negedge clk);
        inst_valid = 1'b0;
        stall = 1'b0;
        flush = 1'b1;

        @(negedge clk);
        inst_valid = 1'b1;
        stall = 1'b0;
        flush = 1'b0;

        @(negedge clk);
        inst_valid = 1'b0;
        stall = 1'b0;
        flush = 1'b0;

        @(posedge clk);

        if (cycle_count !== 32'd4 || instret_count !== 32'd3 || stall_count !== 32'd1 || flush_count !== 32'd1) begin
            $display("FAIL: counters cycle=%0d instret=%0d stall=%0d flush=%0d",
                cycle_count, instret_count, stall_count, flush_count);
            $finish;
        end

        $display("PASS: perf_counter counters are correct");
        $finish;
    end
endmodule
