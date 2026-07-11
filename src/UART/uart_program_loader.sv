`timescale 1ns / 1ps

module uart_program_loader #(
    parameter integer MEM_WORDS = 256
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        packet_valid,
    input  logic        packet_crc_error,
    input  logic [7:0]  request_command,
    input  logic [7:0]  request_sequence,
    input  logic [15:0] request_address,
    input  logic [31:0] request_data,
    input  logic [7:0]  request_flags,
    output logic        response_valid,
    input  logic        response_ready,
    output logic [7:0]  response_status,
    output logic [7:0]  response_sequence,
    output logic [15:0] response_address,
    output logic [7:0]  response_detail,
    output logic        run_mode,
    output logic        imem_write_enable,
    output logic [31:0] imem_write_addr,
    output logic [31:0] imem_write_data,
    output logic [1:0]  loader_state,
    output logic [8:0]  expected_words,
    output logic [8:0]  received_words,
    output logic        error_seen
);
    localparam logic [7:0] CMD_BEGIN  = 8'h01;
    localparam logic [7:0] CMD_WRITE  = 8'h02;
    localparam logic [7:0] CMD_RUN    = 8'h03;
    localparam logic [7:0] CMD_STOP   = 8'h04;
    localparam logic [7:0] CMD_STATUS = 8'h05;

    localparam logic [7:0] STATUS_OK            = 8'h00;
    localparam logic [7:0] STATUS_CRC_ERROR     = 8'h01;
    localparam logic [7:0] STATUS_BAD_COMMAND   = 8'h02;
    localparam logic [7:0] STATUS_BAD_ADDRESS   = 8'h03;
    localparam logic [7:0] STATUS_BAD_STATE     = 8'h04;
    localparam logic [7:0] STATUS_BUSY          = 8'h05;
    localparam logic [7:0] STATUS_INCOMPLETE    = 8'h06;
    localparam logic [7:0] STATUS_BAD_LENGTH    = 8'h07;
    localparam logic [7:0] STATUS_BAD_FLAGS     = 8'h08;
    localparam logic [7:0] STATUS_SEQ_CONFLICT  = 8'h09;

    localparam logic [1:0] STATE_LOAD_IDLE = 2'd0;
    localparam logic [1:0] STATE_CLEARING  = 2'd1;
    localparam logic [1:0] STATE_READY     = 2'd2;
    localparam logic [1:0] STATE_RUNNING   = 2'd3;

    localparam logic [31:0] NOP_INSTRUCTION = 32'h00000013;

    logic [MEM_WORDS-1:0] received_bitmap;
    logic [7:0] clear_index;
    logic clear_drain_pending;
    logic session_active;

    logic write_commit_pending;
    logic [7:0] pending_write_command;
    logic [7:0] pending_write_sequence;
    logic [15:0] pending_write_address;
    logic [31:0] pending_write_data;
    logic [7:0] pending_write_flags;

    logic missing_scan_pending;
    logic [7:0] missing_scan_index;
    logic [7:0] pending_scan_command;
    logic [7:0] pending_scan_sequence;
    logic [15:0] pending_scan_address;
    logic [31:0] pending_scan_data;
    logic [7:0] pending_scan_flags;

    logic [7:0] pending_begin_sequence;
    logic [15:0] pending_begin_address;
    logic [31:0] pending_begin_data;
    logic [7:0] pending_begin_flags;

    logic last_request_valid;
    logic [7:0] last_request_command;
    logic [7:0] last_request_sequence;
    logic [15:0] last_request_address;
    logic [31:0] last_request_data;
    logic [7:0] last_request_flags;
    logic [7:0] last_response_status;
    logic [15:0] last_response_address;
    logic [7:0] last_response_detail;

    wire session_complete = session_active && (expected_words != 0) &&
                            (received_words == expected_words);
    wire exact_duplicate = last_request_valid &&
                           (request_command == last_request_command) &&
                           (request_sequence == last_request_sequence) &&
                           (request_address == last_request_address) &&
                           (request_data == last_request_data) &&
                           (request_flags == last_request_flags);

    task automatic set_response(
        input [7:0] status_in,
        input [7:0] sequence_in,
        input [15:0] address_in,
        input [7:0] detail_in
    );
        begin
            response_valid    <= 1'b1;
            response_status   <= status_in;
            response_sequence <= sequence_in;
            response_address  <= address_in;
            response_detail   <= detail_in;
            if (status_in != STATUS_OK)
                error_seen <= 1'b1;
        end
    endtask

    task automatic set_response_and_cache(
        input [7:0] status_in,
        input [15:0] address_in,
        input [7:0] detail_in
    );
        begin
            set_response(status_in, request_sequence, address_in, detail_in);
            last_request_valid    <= 1'b1;
            last_request_command  <= request_command;
            last_request_sequence <= request_sequence;
            last_request_address  <= request_address;
            last_request_data     <= request_data;
            last_request_flags    <= request_flags;
            last_response_status  <= status_in;
            last_response_address <= address_in;
            last_response_detail  <= detail_in;
        end
    endtask

    always_ff @(posedge clk) begin
        if (reset) begin
            response_valid         <= 1'b0;
            response_status        <= STATUS_OK;
            response_sequence      <= 8'd0;
            response_address       <= 16'd0;
            response_detail        <= 8'd0;
            run_mode               <= 1'b0;
            imem_write_enable      <= 1'b0;
            imem_write_addr        <= 32'd0;
            imem_write_data        <= NOP_INSTRUCTION;
            loader_state           <= STATE_LOAD_IDLE;
            expected_words         <= 9'd0;
            received_words         <= 9'd0;
            received_bitmap        <= '0;
            clear_index            <= 8'd0;
            clear_drain_pending    <= 1'b0;
            session_active         <= 1'b0;
            write_commit_pending   <= 1'b0;
            pending_write_command  <= 8'd0;
            pending_write_sequence <= 8'd0;
            pending_write_address  <= 16'd0;
            pending_write_data     <= 32'd0;
            pending_write_flags    <= 8'd0;
            missing_scan_pending   <= 1'b0;
            missing_scan_index     <= 8'd0;
            pending_scan_command   <= 8'd0;
            pending_scan_sequence  <= 8'd0;
            pending_scan_address   <= 16'd0;
            pending_scan_data      <= 32'd0;
            pending_scan_flags     <= 8'd0;
            pending_begin_sequence <= 8'd0;
            pending_begin_address  <= 16'd0;
            pending_begin_data     <= 32'd0;
            pending_begin_flags    <= 8'd0;
            last_request_valid     <= 1'b0;
            last_request_command   <= 8'd0;
            last_request_sequence  <= 8'd0;
            last_request_address   <= 16'd0;
            last_request_data      <= 32'd0;
            last_request_flags     <= 8'd0;
            last_response_status   <= STATUS_OK;
            last_response_address  <= 16'd0;
            last_response_detail   <= 8'd0;
            error_seen             <= 1'b0;
        end else begin
            imem_write_enable <= 1'b0;

            if (response_valid && response_ready)
                response_valid <= 1'b0;

            if (loader_state == STATE_CLEARING) begin
                if (clear_drain_pending) begin
                    // The IMEM samples the final clear write on this edge.
                    clear_drain_pending <= 1'b0;
                    loader_state <= STATE_READY;
                    session_active <= 1'b1;
                    set_response(STATUS_OK, pending_begin_sequence,
                                 pending_begin_address, 8'd0);
                    last_request_valid    <= 1'b1;
                    last_request_command  <= CMD_BEGIN;
                    last_request_sequence <= pending_begin_sequence;
                    last_request_address  <= pending_begin_address;
                    last_request_data     <= pending_begin_data;
                    last_request_flags    <= pending_begin_flags;
                    last_response_status  <= STATUS_OK;
                    last_response_address <= pending_begin_address;
                    last_response_detail  <= 8'd0;
                end else begin
                    imem_write_enable <= 1'b1;
                    imem_write_addr <= {22'd0, clear_index, 2'b00};
                    imem_write_data <= NOP_INSTRUCTION;
                    if (clear_index == MEM_WORDS - 1)
                        clear_drain_pending <= 1'b1;
                    else
                        clear_index <= clear_index + 1'b1;
                end

                if (!clear_drain_pending && (clear_index != MEM_WORDS - 1) &&
                    packet_valid &&
                    (!response_valid || response_ready)) begin
                    set_response(STATUS_BUSY, request_sequence,
                                 request_address, {6'd0, loader_state});
                end
            end else if (write_commit_pending) begin
                // The IMEM samples the pending WRITE on this edge; ACK afterwards.
                write_commit_pending <= 1'b0;
                if (!received_bitmap[pending_write_address[7:0]]) begin
                    received_bitmap[pending_write_address[7:0]] <= 1'b1;
                    received_words <= received_words + 1'b1;
                end
                set_response(STATUS_OK, pending_write_sequence,
                             pending_write_address, 8'd0);
                last_request_valid    <= 1'b1;
                last_request_command  <= pending_write_command;
                last_request_sequence <= pending_write_sequence;
                last_request_address  <= pending_write_address;
                last_request_data     <= pending_write_data;
                last_request_flags    <= pending_write_flags;
                last_response_status  <= STATUS_OK;
                last_response_address <= pending_write_address;
                last_response_detail  <= 8'd0;
            end else if (missing_scan_pending) begin
                if (!received_bitmap[missing_scan_index]) begin
                    missing_scan_pending <= 1'b0;
                    set_response(STATUS_INCOMPLETE, pending_scan_sequence,
                                 {8'd0, missing_scan_index}, 8'd0);
                    last_request_valid    <= 1'b1;
                    last_request_command  <= pending_scan_command;
                    last_request_sequence <= pending_scan_sequence;
                    last_request_address  <= pending_scan_address;
                    last_request_data     <= pending_scan_data;
                    last_request_flags    <= pending_scan_flags;
                    last_response_status  <= STATUS_INCOMPLETE;
                    last_response_address <= {8'd0, missing_scan_index};
                    last_response_detail  <= 8'd0;
                end else begin
                    missing_scan_index <= missing_scan_index + 1'b1;
                end
            end else if (!response_valid || response_ready) begin
                if (packet_crc_error) begin
                    set_response(STATUS_CRC_ERROR, request_sequence,
                                 request_address, {6'd0, loader_state});
                end else if (packet_valid) begin
                    if (exact_duplicate) begin
                        set_response(last_response_status, request_sequence,
                                     last_response_address, last_response_detail);
                    end else if ((request_sequence == last_request_sequence) &&
                                 last_request_valid) begin
                        set_response(STATUS_SEQ_CONFLICT, request_sequence,
                                     request_address, {6'd0, loader_state});
                    end else begin
                        case (request_command)
                            CMD_BEGIN: begin
                                if (request_flags != 8'd0) begin
                                    set_response_and_cache(STATUS_BAD_FLAGS,
                                                           request_address,
                                                           {6'd0, loader_state});
                                end else if ((request_address == 0) ||
                                    (request_address > MEM_WORDS) ||
                                    (request_data != 0)) begin
                                    set_response_and_cache(STATUS_BAD_LENGTH,
                                                           request_address,
                                                           {6'd0, loader_state});
                                end else begin
                                    run_mode <= 1'b0;
                                    loader_state <= STATE_CLEARING;
                                    expected_words <= request_address[8:0];
                                    received_words <= 9'd0;
                                    received_bitmap <= '0;
                                    clear_index <= 8'd0;
                                    clear_drain_pending <= 1'b0;
                                    write_commit_pending <= 1'b0;
                                    missing_scan_pending <= 1'b0;
                                    session_active <= 1'b0;
                                    pending_begin_sequence <= request_sequence;
                                    pending_begin_address <= request_address;
                                    pending_begin_data <= request_data;
                                    pending_begin_flags <= request_flags;
                                    error_seen <= 1'b0;
                                end
                            end

                            CMD_WRITE: begin
                                if (request_flags != 8'd0) begin
                                    set_response_and_cache(STATUS_BAD_FLAGS,
                                                           request_address,
                                                           {6'd0, loader_state});
                                end else if ((loader_state != STATE_READY) || !session_active) begin
                                    set_response_and_cache(STATUS_BAD_STATE,
                                                           request_address,
                                                           {6'd0, loader_state});
                                end else if ((request_address[15:8] != 0) ||
                                             ({1'b0, request_address[7:0]} >= expected_words)) begin
                                    set_response_and_cache(STATUS_BAD_ADDRESS,
                                                           request_address,
                                                           {6'd0, loader_state});
                                end else begin
                                    imem_write_enable <= 1'b1;
                                    imem_write_addr <= {14'd0, request_address, 2'b00};
                                    imem_write_data <= request_data;
                                    write_commit_pending <= 1'b1;
                                    pending_write_command <= request_command;
                                    pending_write_sequence <= request_sequence;
                                    pending_write_address <= request_address;
                                    pending_write_data <= request_data;
                                    pending_write_flags <= request_flags;
                                end
                            end

                            CMD_RUN: begin
                                if (request_flags != 8'd0) begin
                                    set_response_and_cache(STATUS_BAD_FLAGS,
                                                           request_address,
                                                           {6'd0, loader_state});
                                end else if (request_address != 0) begin
                                    set_response_and_cache(STATUS_BAD_ADDRESS,
                                                           request_address,
                                                           {6'd0, loader_state});
                                end else if (request_data != 0) begin
                                    set_response_and_cache(STATUS_BAD_LENGTH,
                                                           request_address,
                                                           {6'd0, loader_state});
                                end else if ((loader_state != STATE_READY) || !session_active) begin
                                    set_response_and_cache(STATUS_BAD_STATE,
                                                           request_address,
                                                           {6'd0, loader_state});
                                end else if (!session_complete) begin
                                    missing_scan_pending <= 1'b1;
                                    missing_scan_index <= 8'd0;
                                    pending_scan_command <= request_command;
                                    pending_scan_sequence <= request_sequence;
                                    pending_scan_address <= request_address;
                                    pending_scan_data <= request_data;
                                    pending_scan_flags <= request_flags;
                                end else begin
                                    run_mode <= 1'b1;
                                    loader_state <= STATE_RUNNING;
                                    set_response_and_cache(STATUS_OK,
                                                           {7'd0, received_words}, 8'd0);
                                end
                            end

                            CMD_STOP: begin
                                if (request_flags != 8'd0) begin
                                    set_response_and_cache(STATUS_BAD_FLAGS,
                                                           request_address,
                                                           {6'd0, loader_state});
                                end else if (request_address != 0) begin
                                    set_response_and_cache(STATUS_BAD_ADDRESS,
                                                           request_address,
                                                           {6'd0, loader_state});
                                end else if (request_data != 0) begin
                                    set_response_and_cache(STATUS_BAD_LENGTH,
                                                           request_address,
                                                           {6'd0, loader_state});
                                end else begin
                                    run_mode <= 1'b0;
                                    if (session_active)
                                        loader_state <= STATE_READY;
                                    else
                                        loader_state <= STATE_LOAD_IDLE;
                                    set_response_and_cache(STATUS_OK,
                                                           {7'd0, received_words}, 8'd0);
                                end
                            end

                            CMD_STATUS: begin
                                if (request_flags != 8'd0) begin
                                    set_response_and_cache(STATUS_BAD_FLAGS,
                                                           request_address,
                                                           {6'd0, loader_state});
                                end else if (request_address != 0) begin
                                    set_response_and_cache(STATUS_BAD_ADDRESS,
                                                           request_address,
                                                           {6'd0, loader_state});
                                end else if (request_data != 0) begin
                                    set_response_and_cache(STATUS_BAD_LENGTH,
                                                           request_address,
                                                           {6'd0, loader_state});
                                end else begin
                                    set_response_and_cache(
                                        STATUS_OK,
                                        {7'd0, received_words},
                                        {4'd0, session_complete, session_active, loader_state}
                                    );
                                end
                            end

                            default: begin
                                set_response_and_cache(STATUS_BAD_COMMAND,
                                                       request_address,
                                                       {6'd0, loader_state});
                            end
                        endcase
                    end
                end
            end
        end
    end
endmodule
