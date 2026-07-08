`timescale 1ns/1ps

module tb_io_system;
    reg clk;
    reg rst;
    reg [7:0] sw;
    wire [7:0] led;
    wire [31:0] debug_pc;
    wire [31:0] debug_dmem0;
    wire [31:0] debug_cycle_count;
    wire [31:0] debug_instret_count;

    system_top #(.INIT_FILE("io_led.mem")) dut(
        .clk(clk),
        .rst(rst),
        .sw(sw),
        .led(led),
        .debug_pc(debug_pc),
        .debug_dmem0(debug_dmem0),
        .debug_cycle_count(debug_cycle_count),
        .debug_instret_count(debug_instret_count)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        sw = 8'ha5;
        rst = 1'b1;
        #20;
        rst = 1'b0;
        repeat (30) @(posedge clk);

        if (led !== 8'h55) begin
            $display("FAIL: io_led expected led=0x55, got 0x%02h", led);
            $finish;
        end

        if (debug_cycle_count == 32'b0 || debug_instret_count == 32'b0) begin
            $display("FAIL: performance counters did not increment");
            $finish;
        end

        $display("PASS: memory-mapped LED I/O and counters worked, cycles=%0d instret=%0d", debug_cycle_count, debug_instret_count);
        $finish;
    end
endmodule
