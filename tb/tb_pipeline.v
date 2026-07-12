`timescale 1ns/1ps

module tb_pipeline;
    reg clk;
    reg rst;

    wire nop_stall;
    wire nop_flush;
    wire nop_valid;
    wire [31:0] nop_cycle_count;
    wire [31:0] nop_instret_count;
    wire [31:0] nop_stall_count;
    wire [31:0] nop_flush_count;
    wire [31:0] nop_pc;
    wire [31:0] nop_dmem0;
    wire [31:0] nop_dmem1;

    wire hazard_stall;
    wire hazard_flush;
    wire hazard_valid;
    wire [31:0] hazard_cycle_count;
    wire [31:0] hazard_instret_count;
    wire [31:0] hazard_stall_count;
    wire [31:0] hazard_flush_count;
    wire [31:0] hazard_pc;
    wire [31:0] hazard_dmem0;
    wire [31:0] hazard_dmem1;

    wire load_stall;
    wire load_flush;
    wire load_valid;
    wire [31:0] load_cycle_count;
    wire [31:0] load_instret_count;
    wire [31:0] load_stall_count;
    wire [31:0] load_flush_count;
    wire [31:0] load_pc;
    wire [31:0] load_dmem0;
    wire [31:0] load_dmem1;

    wire branch_stall;
    wire branch_flush;
    wire branch_predict_taken;
    wire branch_valid;
    wire [31:0] branch_cycle_count;
    wire [31:0] branch_instret_count;
    wire [31:0] branch_stall_count;
    wire [31:0] branch_flush_count;
    wire [31:0] branch_pc;
    wire [31:0] branch_dmem0;
    wire [31:0] branch_dmem1;

    wire pred_stall;
    wire pred_flush;
    wire pred_predict_taken;
    wire pred_valid;
    wire [31:0] pred_cycle_count;
    wire [31:0] pred_instret_count;
    wire [31:0] pred_stall_count;
    wire [31:0] pred_flush_count;
    wire [31:0] pred_pc;
    wire [31:0] pred_dmem0;
    wire [31:0] pred_dmem1;

    reg load_stall_seen;
    reg branch_flush_seen;
    reg branch_predict_seen;

    pipeline_cpu_top #(.INIT_FILE("pipeline_nop.mem")) dut_nop(
        .clk(clk),
        .rst(rst),
        .debug_imem_index(8'b0),
        .debug_dmem_index(8'b0),
        .debug_reg_index(5'b0),
        .stall_debug(nop_stall),
        .flush_debug(nop_flush),
        .inst_valid_debug(nop_valid),
        .debug_cycle_count(nop_cycle_count),
        .debug_instret_count(nop_instret_count),
        .debug_stall_count(nop_stall_count),
        .debug_flush_count(nop_flush_count),
        .debug_pc(nop_pc),
        .debug_dmem0(nop_dmem0),
        .debug_dmem1(nop_dmem1),
        .debug_dmem_data(),
        .debug_imem_data(),
        .debug_reg_data()
    );

    pipeline_cpu_top #(.INIT_FILE("hazard.mem")) dut_hazard(
        .clk(clk),
        .rst(rst),
        .debug_imem_index(8'b0),
        .debug_dmem_index(8'b0),
        .debug_reg_index(5'b0),
        .stall_debug(hazard_stall),
        .flush_debug(hazard_flush),
        .inst_valid_debug(hazard_valid),
        .debug_cycle_count(hazard_cycle_count),
        .debug_instret_count(hazard_instret_count),
        .debug_stall_count(hazard_stall_count),
        .debug_flush_count(hazard_flush_count),
        .debug_pc(hazard_pc),
        .debug_dmem0(hazard_dmem0),
        .debug_dmem1(hazard_dmem1),
        .debug_dmem_data(),
        .debug_imem_data(),
        .debug_reg_data()
    );

    pipeline_cpu_top #(.INIT_FILE("load_use.mem")) dut_load(
        .clk(clk),
        .rst(rst),
        .debug_imem_index(8'b0),
        .debug_dmem_index(8'b0),
        .debug_reg_index(5'b0),
        .stall_debug(load_stall),
        .flush_debug(load_flush),
        .inst_valid_debug(load_valid),
        .debug_cycle_count(load_cycle_count),
        .debug_instret_count(load_instret_count),
        .debug_stall_count(load_stall_count),
        .debug_flush_count(load_flush_count),
        .debug_pc(load_pc),
        .debug_dmem0(load_dmem0),
        .debug_dmem1(load_dmem1),
        .debug_dmem_data(),
        .debug_imem_data(),
        .debug_reg_data()
    );

    pipeline_cpu_top #(.INIT_FILE("branch.mem")) dut_branch(
        .clk(clk),
        .rst(rst),
        .debug_imem_index(8'b0),
        .debug_dmem_index(8'b0),
        .debug_reg_index(5'b0),
        .stall_debug(branch_stall),
        .flush_debug(branch_flush),
        .predict_taken_debug(branch_predict_taken),
        .inst_valid_debug(branch_valid),
        .debug_cycle_count(branch_cycle_count),
        .debug_instret_count(branch_instret_count),
        .debug_stall_count(branch_stall_count),
        .debug_flush_count(branch_flush_count),
        .debug_pc(branch_pc),
        .debug_dmem0(branch_dmem0),
        .debug_dmem1(branch_dmem1),
        .debug_dmem_data(),
        .debug_imem_data(),
        .debug_reg_data()
    );

    pipeline_cpu_top #(.INIT_FILE("branch_predict.mem")) dut_pred(
        .clk(clk),
        .rst(rst),
        .debug_imem_index(8'b0),
        .debug_dmem_index(8'b0),
        .debug_reg_index(5'b0),
        .stall_debug(pred_stall),
        .flush_debug(pred_flush),
        .predict_taken_debug(pred_predict_taken),
        .inst_valid_debug(pred_valid),
        .debug_cycle_count(pred_cycle_count),
        .debug_instret_count(pred_instret_count),
        .debug_stall_count(pred_stall_count),
        .debug_flush_count(pred_flush_count),
        .debug_pc(pred_pc),
        .debug_dmem0(pred_dmem0),
        .debug_dmem1(pred_dmem1),
        .debug_dmem_data(),
        .debug_imem_data(),
        .debug_reg_data()
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            load_stall_seen <= 1'b0;
            branch_flush_seen <= 1'b0;
            branch_predict_seen <= 1'b0;
        end else begin
            if (load_stall) begin
                load_stall_seen <= 1'b1;
            end
            if (branch_flush) begin
                branch_flush_seen <= 1'b1;
            end
            if (branch_predict_taken || pred_predict_taken) begin
                branch_predict_seen <= 1'b1;
            end
        end
    end

    initial begin
        rst = 1'b1;
        #20;
        rst = 1'b0;
        repeat (80) @(posedge clk);

        if (nop_dmem0 !== 32'd2) begin
            $display("FAIL: pipeline_nop expected dmem[0]=2, got %0d", nop_dmem0);
            $finish;
        end

        if (hazard_dmem0 !== 32'd5) begin
            $display("FAIL: hazard expected dmem[0]=5, got %0d", hazard_dmem0);
            $finish;
        end

        if (load_dmem1 !== 32'd200) begin
            $display("FAIL: load_use expected dmem[1]=200, got %0d", load_dmem1);
            $finish;
        end

        if (!load_stall_seen) begin
            $display("FAIL: load_use did not raise stall_debug");
            $finish;
        end

        if (load_stall_count == 32'b0) begin
            $display("FAIL: load_use stall counter did not increment");
            $finish;
        end

        if (branch_dmem0 !== 32'd7) begin
            $display("FAIL: branch expected dmem[0]=7, got %0d", branch_dmem0);
            $finish;
        end

        if (!branch_flush_seen) begin
            $display("FAIL: branch did not raise flush_debug");
            $finish;
        end

        if (branch_flush_count == 32'b0) begin
            $display("FAIL: branch flush counter did not increment");
            $finish;
        end

        if (pred_dmem0 !== 32'd1) begin
            $display("FAIL: branch_predict expected dmem[0]=1, got %0d", pred_dmem0);
            $finish;
        end

        if (!branch_predict_seen) begin
            $display("FAIL: branch predictor did not raise predict_taken_debug");
            $finish;
        end

        $display("PERF pipeline_nop: cycle=%0d instret=%0d stall=%0d flush=%0d",
            nop_cycle_count, nop_instret_count, nop_stall_count, nop_flush_count);
        $display("PERF hazard: cycle=%0d instret=%0d stall=%0d flush=%0d",
            hazard_cycle_count, hazard_instret_count, hazard_stall_count, hazard_flush_count);
        $display("PERF load_use: cycle=%0d instret=%0d stall=%0d flush=%0d",
            load_cycle_count, load_instret_count, load_stall_count, load_flush_count);
        $display("PERF branch: cycle=%0d instret=%0d stall=%0d flush=%0d",
            branch_cycle_count, branch_instret_count, branch_stall_count, branch_flush_count);
        $display("PERF branch_predict: cycle=%0d instret=%0d stall=%0d flush=%0d",
            pred_cycle_count, pred_instret_count, pred_stall_count, pred_flush_count);
        $display("PASS: pipeline nop, forwarding, load-use stall, branch prediction, and branch flush tests passed");
        $finish;
    end
endmodule
