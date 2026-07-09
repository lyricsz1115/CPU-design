`timescale 1ns/1ps

module tb_editable_loader;
    reg clk;
    reg rst_btn;
    reg [7:0] sw;
    reg btn_write;
    reg btn_next;
    reg btn_clear;
    reg btn_run;
    wire [7:0] led;

    editable_minisys_top dut(
        .clk(clk),
        .rst_btn(rst_btn),
        .sw(sw),
        .btn_write(btn_write),
        .btn_next(btn_next),
        .btn_clear(btn_clear),
        .btn_run(btn_run),
        .led(led)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task pulse_write;
        input [7:0] value;
        begin
            sw = value;
            @(negedge clk);
            btn_write = 1'b1;
            @(posedge clk);
            @(negedge clk);
            btn_write = 1'b0;
            @(posedge clk);
        end
    endtask

    task pulse_run;
        begin
            @(negedge clk);
            btn_run = 1'b1;
            @(posedge clk);
            @(negedge clk);
            btn_run = 1'b0;
            @(posedge clk);
        end
    endtask

    task load_word;
        input [31:0] word;
        begin
            pulse_write(word[7:0]);
            pulse_write(word[15:8]);
            pulse_write(word[23:16]);
            pulse_write(word[31:24]);
        end
    endtask

    initial begin
        rst_btn = 1'b1;
        sw = 8'b0;
        btn_write = 1'b0;
        btn_next = 1'b0;
        btn_clear = 1'b0;
        btn_run = 1'b0;
        repeat (4) @(posedge clk);
        rst_btn = 1'b0;

        load_word(32'h00000093);
        load_word(32'h00100113);
        load_word(32'h00b00193);
        load_word(32'h002080b3);
        load_word(32'h00110113);
        load_word(32'h00310463);
        load_word(32'hff5ff06f);
        load_word(32'h00102023);
        load_word(32'h0000006f);

        pulse_run();
        repeat (120) @(posedge clk);

        if (led !== 8'h37) begin
            $display("FAIL: editable loader expected led=0x37, got 0x%02h", led);
            $display("DEBUG: run_mode=%0d pc=0x%08h dmem0=0x%08h instr_index=%0d byte_index=%0d",
                dut.run_mode, dut.debug_pc, dut.debug_dmem0, dut.instr_index, dut.byte_index);
            $display("DEBUG imem[0]=0x%08h imem[1]=0x%08h imem[2]=0x%08h imem[3]=0x%08h",
                dut.u_cpu.u_imem.mem[0], dut.u_cpu.u_imem.mem[1], dut.u_cpu.u_imem.mem[2], dut.u_cpu.u_imem.mem[3]);
            $display("DEBUG imem[4]=0x%08h imem[5]=0x%08h imem[6]=0x%08h imem[7]=0x%08h imem[8]=0x%08h",
                dut.u_cpu.u_imem.mem[4], dut.u_cpu.u_imem.mem[5], dut.u_cpu.u_imem.mem[6], dut.u_cpu.u_imem.mem[7], dut.u_cpu.u_imem.mem[8]);
            $finish;
        end

        $display("PASS: editable loader wrote instructions through switches/buttons and CPU produced led=0x37");
        $finish;
    end
endmodule
