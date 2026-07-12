`timescale 1ns / 1ps

module tb_uart_program_packet_rx;
    logic clk;
    logic reset;
    logic [7:0] rx_data;
    logic rx_valid;
    logic rx_framing_error;
    logic packet_valid;
    logic crc_error;
    logic timeout_error;
    logic [7:0] command;
    logic [7:0] sequence_number;
    logic [15:0] word_address;
    logic [31:0] word_data;
    logic [7:0] flags;
    logic timeout_seen;

    uart_program_packet_rx #(
        .CLK_HZ(1_000_000),
        .BYTE_TIMEOUT_US(20)
    ) dut (
        .clk(clk),
        .reset(reset),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .rx_framing_error(rx_framing_error),
        .packet_valid(packet_valid),
        .crc_error(crc_error),
        .timeout_error(timeout_error),
        .command(command),
        .sequence_number(sequence_number),
        .word_address(word_address),
        .word_data(word_data),
        .flags(flags)
    );

    always #5 clk = ~clk;

    always_ff @(posedge clk) begin
        if (reset)
            timeout_seen <= 1'b0;
        else if (timeout_error)
            timeout_seen <= 1'b1;
    end

    function automatic [7:0] crc8_next(input [7:0] crc_in, input [7:0] data_in);
        integer i;
        reg [7:0] value;
        begin
            value = crc_in ^ data_in;
            for (i = 0; i < 8; i = i + 1) begin
                if (value[7])
                    value = (value << 1) ^ 8'h07;
                else
                    value = value << 1;
            end
            crc8_next = value;
        end
    endfunction

    task automatic send_byte(input [7:0] value);
        begin
            @(negedge clk);
            rx_data = value;
            rx_valid = 1'b1;
            @(negedge clk);
            rx_valid = 1'b0;
        end
    endtask

    task automatic send_request(
        input [7:0] cmd,
        input [7:0] seq,
        input [15:0] addr,
        input [31:0] data,
        input [7:0] req_flags,
        input bit corrupt_crc
    );
        reg [7:0] crc;
        begin
            crc = 8'd0;
            send_byte(8'hAA); crc = crc8_next(crc, 8'hAA);
            send_byte(8'h49); crc = crc8_next(crc, 8'h49);
            send_byte(cmd); crc = crc8_next(crc, cmd);
            send_byte(seq); crc = crc8_next(crc, seq);
            send_byte(addr[7:0]); crc = crc8_next(crc, addr[7:0]);
            send_byte(addr[15:8]); crc = crc8_next(crc, addr[15:8]);
            send_byte(data[7:0]); crc = crc8_next(crc, data[7:0]);
            send_byte(data[15:8]); crc = crc8_next(crc, data[15:8]);
            send_byte(data[23:16]); crc = crc8_next(crc, data[23:16]);
            send_byte(data[31:24]); crc = crc8_next(crc, data[31:24]);
            send_byte(req_flags); crc = crc8_next(crc, req_flags);
            send_byte(corrupt_crc ? (crc ^ 8'h01) : crc);
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        rx_data = 8'd0;
        rx_valid = 1'b0;
        rx_framing_error = 1'b0;
        repeat (4) @(posedge clk);
        reset = 1'b0;

        send_request(8'h02, 8'h11, 16'h00AA, 32'hAA5500FF, 8'h00, 1'b0);
        if (!packet_valid || command != 8'h02 || sequence_number != 8'h11 ||
            word_address != 16'h00AA || word_data != 32'hAA5500FF || flags != 0)
            $fatal(1, "valid request was not decoded correctly");

        send_request(8'h02, 8'h12, 16'h0001, 32'h12345678, 8'h00, 1'b1);
        if (!crc_error || packet_valid)
            $fatal(1, "bad CRC was not rejected");

        send_byte(8'h00);
        send_byte(8'hAA);
        send_byte(8'h49);
        send_byte(8'h02);
        repeat (25) @(posedge clk);
        if (!timeout_seen)
            $fatal(1, "partial packet timeout was not detected");

        send_request(8'h05, 8'h13, 16'h0000, 32'h00000000, 8'h00, 1'b0);
        if (!packet_valid || command != 8'h05 || sequence_number != 8'h13)
            $fatal(1, "parser did not recover after timeout");

        @(negedge clk);
        rx_framing_error = 1'b1;
        @(negedge clk);
        rx_framing_error = 1'b0;
        send_request(8'h03, 8'h14, 16'h0000, 32'h00000000, 8'h00, 1'b0);
        if (!packet_valid || command != 8'h03)
            $fatal(1, "parser did not recover after framing error");

        $display("PASS: uart_program_packet_rx framing, CRC, timeout, and resync");
        $finish;
    end
endmodule
