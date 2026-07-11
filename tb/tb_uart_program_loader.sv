`timescale 1ns / 1ps

module tb_uart_program_loader;
    localparam integer MEM_WORDS = 8;

    logic clk;
    logic reset;
    logic packet_valid;
    logic packet_crc_error;
    logic [7:0] request_command;
    logic [7:0] request_sequence;
    logic [15:0] request_address;
    logic [31:0] request_data;
    logic [7:0] request_flags;
    logic response_valid;
    logic response_ready;
    logic [7:0] response_status;
    logic [7:0] response_sequence;
    logic [15:0] response_address;
    logic [7:0] response_detail;
    logic run_mode;
    logic imem_write_enable;
    logic [31:0] imem_write_addr;
    logic [31:0] imem_write_data;
    logic [1:0] loader_state;
    logic [8:0] expected_words;
    logic [8:0] received_words;
    logic error_seen;
    logic [31:0] imem_model [0:MEM_WORDS-1];
    integer i;

    uart_program_loader #(
        .MEM_WORDS(MEM_WORDS)
    ) dut (
        .clk(clk),
        .reset(reset),
        .packet_valid(packet_valid),
        .packet_crc_error(packet_crc_error),
        .request_command(request_command),
        .request_sequence(request_sequence),
        .request_address(request_address),
        .request_data(request_data),
        .request_flags(request_flags),
        .response_valid(response_valid),
        .response_ready(response_ready),
        .response_status(response_status),
        .response_sequence(response_sequence),
        .response_address(response_address),
        .response_detail(response_detail),
        .run_mode(run_mode),
        .imem_write_enable(imem_write_enable),
        .imem_write_addr(imem_write_addr),
        .imem_write_data(imem_write_data),
        .loader_state(loader_state),
        .expected_words(expected_words),
        .received_words(received_words),
        .error_seen(error_seen)
    );

    always #5 clk = ~clk;

    always_ff @(posedge clk) begin
        if (imem_write_enable)
            imem_model[imem_write_addr[4:2]] <= imem_write_data;
    end

    task automatic send_request(
        input [7:0] cmd,
        input [7:0] seq,
        input [15:0] addr,
        input [31:0] data,
        input [7:0] req_flags
    );
        begin
            @(negedge clk);
            request_command = cmd;
            request_sequence = seq;
            request_address = addr;
            request_data = data;
            request_flags = req_flags;
            packet_valid = 1'b1;
            @(negedge clk);
            packet_valid = 1'b0;
        end
    endtask

    task automatic expect_response(
        input [7:0] expected_status,
        input [7:0] expected_sequence,
        input [15:0] expected_address
    );
        integer guard;
        begin
            guard = 0;
            while (!response_valid && guard < 100) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if (!response_valid)
                $fatal(1, "response timeout");
            if (response_status != expected_status ||
                response_sequence != expected_sequence ||
                response_address != expected_address)
                $fatal(1, "unexpected response status=%02h seq=%02h addr=%04h",
                       response_status, response_sequence, response_address);
            @(negedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        packet_valid = 1'b0;
        packet_crc_error = 1'b0;
        request_command = 8'd0;
        request_sequence = 8'd0;
        request_address = 16'd0;
        request_data = 32'd0;
        request_flags = 8'd0;
        response_ready = 1'b1;
        for (i = 0; i < MEM_WORDS; i = i + 1)
            imem_model[i] = 32'hDEADBEEF;

        repeat (4) @(posedge clk);
        reset = 1'b0;

        send_request(8'h01, 8'h01, 16'd3, 32'd0, 8'd0);
        expect_response(8'h00, 8'h01, 16'd3);
        if (loader_state != 2'd2 || expected_words != 3 || received_words != 0)
            $fatal(1, "BEGIN did not enter READY state");
        for (i = 0; i < MEM_WORDS; i = i + 1) begin
            if (imem_model[i] != 32'h00000013)
                $fatal(1, "BEGIN failed to clear IMEM word %0d", i);
        end

        send_request(8'h02, 8'h02, 16'd0, 32'h00000093, 8'd0);
        expect_response(8'h00, 8'h02, 16'd0);
        if (received_words != 1 || imem_model[0] != 32'h00000093)
            $fatal(1, "WRITE word 0 did not commit before ACK");

        send_request(8'h02, 8'h02, 16'd0, 32'h00000093, 8'd0);
        expect_response(8'h00, 8'h02, 16'd0);
        if (received_words != 1)
            $fatal(1, "duplicate WRITE changed received count");

        send_request(8'h02, 8'h02, 16'd1, 32'h00100113, 8'd0);
        expect_response(8'h09, 8'h02, 16'd1);

        send_request(8'h02, 8'h03, 16'd1, 32'h00100113, 8'd0);
        expect_response(8'h00, 8'h03, 16'd1);

        send_request(8'h03, 8'h04, 16'd0, 32'd0, 8'd0);
        expect_response(8'h06, 8'h04, 16'd2);
        if (run_mode)
            $fatal(1, "incomplete program was allowed to run");

        send_request(8'h02, 8'h05, 16'd2, 32'h0000006F, 8'd0);
        expect_response(8'h00, 8'h05, 16'd2);
        send_request(8'h03, 8'h06, 16'd0, 32'd0, 8'd0);
        expect_response(8'h00, 8'h06, 16'd3);
        if (!run_mode || loader_state != 2'd3)
            $fatal(1, "complete program did not enter RUNNING state");

        send_request(8'h04, 8'h07, 16'd0, 32'd0, 8'd0);
        expect_response(8'h00, 8'h07, 16'd3);
        if (run_mode || loader_state != 2'd2)
            $fatal(1, "STOP did not return to READY state");

        @(negedge clk);
        request_sequence = 8'h08;
        request_address = 16'd0;
        packet_crc_error = 1'b1;
        @(negedge clk);
        packet_crc_error = 1'b0;
        expect_response(8'h01, 8'h08, 16'd0);

        $display("PASS: uart_program_loader clear, commit, retry, gating, and errors");
        $finish;
    end
endmodule
