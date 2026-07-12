`timescale 1ns / 1ps

module tb_uart_pipeline_system;
    localparam integer CLKS_PER_BIT = 10;

    logic clk;
    logic rst_btn;
    logic [7:0] sw;
    logic btn_write;
    logic btn_next;
    logic btn_clear;
    logic btn_run;
    logic btn_display_mode;
    logic uart_rx;
    logic uart_tx;
    logic [7:0] led;
    logic mode_led_imem;
    logic mode_led_dmem;
    logic mode_led_reg;
    logic [7:0] seg_an;
    logic [7:0] seg_out;
    integer i;
    logic [31:0] program_words [0:8];

    uart_editable_pipeline_system_top #(
        .UART_CLK_HZ(1_000_000),
        .UART_BAUD(100_000)
    ) dut (
        .clk(clk),
        .rst_btn(rst_btn),
        .sw(sw),
        .btn_write(btn_write),
        .btn_next(btn_next),
        .btn_clear(btn_clear),
        .btn_run(btn_run),
        .btn_display_mode(btn_display_mode),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .led(led),
        .mode_led_imem(mode_led_imem),
        .mode_led_dmem(mode_led_dmem),
        .mode_led_reg(mode_led_reg),
        .seg_an(seg_an),
        .seg_out(seg_out)
    );

    always #5 clk = ~clk;

    initial begin
        #5_000_000;
        $fatal(1, "global simulation timeout");
    end

    function automatic [7:0] crc8_next(input [7:0] crc_in, input [7:0] data_in);
        integer bit_index;
        reg [7:0] value;
        begin
            value = crc_in ^ data_in;
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                if (value[7])
                    value = (value << 1) ^ 8'h07;
                else
                    value = value << 1;
            end
            crc8_next = value;
        end
    endfunction

    task automatic uart_send_byte(input [7:0] value);
        integer bit_index;
        begin
            @(negedge clk);
            uart_rx = 1'b0;
            repeat (CLKS_PER_BIT) @(posedge clk);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                @(negedge clk);
                uart_rx = value[bit_index];
                repeat (CLKS_PER_BIT) @(posedge clk);
            end
            @(negedge clk);
            uart_rx = 1'b1;
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
    endtask

    task automatic uart_send_request(
        input [7:0] cmd,
        input [7:0] seq,
        input [15:0] addr,
        input [31:0] data
    );
        reg [7:0] crc;
        begin
            crc = 8'd0;
            uart_send_byte(8'hAA); crc = crc8_next(crc, 8'hAA);
            uart_send_byte(8'h49); crc = crc8_next(crc, 8'h49);
            uart_send_byte(cmd); crc = crc8_next(crc, cmd);
            uart_send_byte(seq); crc = crc8_next(crc, seq);
            uart_send_byte(addr[7:0]); crc = crc8_next(crc, addr[7:0]);
            uart_send_byte(addr[15:8]); crc = crc8_next(crc, addr[15:8]);
            uart_send_byte(data[7:0]); crc = crc8_next(crc, data[7:0]);
            uart_send_byte(data[15:8]); crc = crc8_next(crc, data[15:8]);
            uart_send_byte(data[23:16]); crc = crc8_next(crc, data[23:16]);
            uart_send_byte(data[31:24]); crc = crc8_next(crc, data[31:24]);
            uart_send_byte(8'h00); crc = crc8_next(crc, 8'h00);
            uart_send_byte(crc);
        end
    endtask

    task automatic uart_receive_byte(output reg [7:0] value);
        integer bit_index;
        begin
            wait (uart_tx === 1'b0);
            repeat (CLKS_PER_BIT / 2) @(posedge clk);
            if (uart_tx !== 1'b0)
                $fatal(1, "invalid UART TX start bit");
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                repeat (CLKS_PER_BIT) @(posedge clk);
                value[bit_index] = uart_tx;
            end
            repeat (CLKS_PER_BIT) @(posedge clk);
            if (uart_tx !== 1'b1)
                $fatal(1, "invalid UART TX stop bit");
        end
    endtask

    task automatic wait_for_response(
        input [7:0] expected_status,
        input [7:0] expected_sequence
    );
        integer byte_index;
        reg [7:0] response_bytes [0:7];
        reg [7:0] crc;
        begin
            for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1)
                uart_receive_byte(response_bytes[byte_index]);
            if (response_bytes[0] != 8'hAA || response_bytes[1] != 8'h41)
                $fatal(1, "invalid response header");
            if (response_bytes[2] != expected_status ||
                response_bytes[3] != expected_sequence) begin
                $fatal(1, "unexpected response status=%02h seq=%02h",
                       response_bytes[2], response_bytes[3]);
            end
            crc = 8'd0;
            for (byte_index = 0; byte_index < 7; byte_index = byte_index + 1)
                crc = crc8_next(crc, response_bytes[byte_index]);
            if (response_bytes[7] != crc)
                $fatal(1, "invalid response CRC expected=%02h actual=%02h",
                       crc, response_bytes[7]);
        end
    endtask

    initial begin
        program_words[0] = 32'h00000093;
        program_words[1] = 32'h00100113;
        program_words[2] = 32'h00B00193;
        program_words[3] = 32'h002080B3;
        program_words[4] = 32'h00110113;
        program_words[5] = 32'h00310463;
        program_words[6] = 32'hFF5FF06F;
        program_words[7] = 32'h00102023;
        program_words[8] = 32'h0000006F;

        clk = 1'b0;
        rst_btn = 1'b1;
        sw = 8'd0;
        btn_write = 1'b0;
        btn_next = 1'b0;
        btn_clear = 1'b0;
        btn_run = 1'b0;
        btn_display_mode = 1'b0;
        uart_rx = 1'b1;
        repeat (10) @(posedge clk);
        rst_btn = 1'b0;
        repeat (10) @(posedge clk);

        uart_send_request(8'h01, 8'h01, 16'd9, 32'd0);
        wait_for_response(8'h00, 8'h01);

        for (i = 0; i < 9; i = i + 1) begin
            uart_send_request(8'h02, i + 2, i[15:0], program_words[i]);
            wait_for_response(8'h00, i + 2);
        end

        for (i = 0; i < 9; i = i + 1) begin
            if (dut.u_cpu.u_imem.mem[i] != program_words[i]) begin
                $fatal(1, "IMEM mismatch at %0d expected=%08h actual=%08h",
                       i, program_words[i], dut.u_cpu.u_imem.mem[i]);
            end
        end

        uart_send_request(8'h03, 8'h0B, 16'd0, 32'd0);
        wait_for_response(8'h00, 8'h0B);
        repeat (1000) @(posedge clk);

        if (led != 8'h37)
            $fatal(1, "UART-loaded pipeline program failed led=%02h run=%0d rst=%0d pc=%08h if_inst=%08h id_inst=%08h id_we=%0d wb_we=%0d wb_rd=%0d x1=%08h x2=%08h io_mem0=%08h internal_mem0=%08h",
                   led, dut.run_mode, dut.cpu_rst, dut.debug_pc, dut.u_cpu.inst_if,
                   dut.u_cpu.if_id_inst, dut.u_cpu.id_reg_write,
                   dut.u_cpu.wb_reg_write, dut.u_cpu.wb_rd,
                   dut.u_cpu.u_regfile.regs[1],
                   dut.u_cpu.u_regfile.regs[2], dut.u_io_bus.mem[0],
                   dut.u_cpu.u_dmem.mem[0]);

        $display("PASS: UART-loaded sum program produced led=0x37");
        $finish;
    end
endmodule
