`timescale 1ns / 1ps

module uart_response_packet_tx #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BAUD   = 115_200
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        response_valid,
    output logic        response_ready,
    input  logic [7:0]  status,
    input  logic [7:0]  sequence_number,
    input  logic [15:0] word_address,
    input  logic [7:0]  detail,
    output logic        tx,
    output logic        busy,
    output logic        sent_pulse
);
    localparam logic [7:0] SOF0 = 8'hAA;
    localparam logic [7:0] SOF1 = 8'h41;

    localparam logic [1:0] STATE_IDLE = 2'd0;
    localparam logic [1:0] STATE_CRC  = 2'd1;
    localparam logic [1:0] STATE_LOAD = 2'd2;
    localparam logic [1:0] STATE_WAIT = 2'd3;

    logic [1:0] state;
    logic [2:0] byte_index;
    logic [7:0] packet [0:7];
    logic [7:0] crc_value;
    logic [7:0] tx_data;
    logic tx_start;
    logic tx_busy;
    logic tx_done;

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

    assign response_ready = (state == STATE_IDLE);
    assign busy = (state != STATE_IDLE) || tx_busy;

    uart_tx_byte #(
        .CLK_HZ(CLK_HZ),
        .BAUD(BAUD)
    ) u_tx_byte (
        .clk(clk),
        .reset(reset),
        .data(tx_data),
        .start(tx_start),
        .tx(tx),
        .busy(tx_busy),
        .done(tx_done)
    );

    always_ff @(posedge clk) begin
        if (reset) begin
            state       <= STATE_IDLE;
            byte_index  <= 3'd0;
            crc_value   <= 8'd0;
            tx_data     <= 8'd0;
            tx_start    <= 1'b0;
            sent_pulse  <= 1'b0;
            packet[0]   <= 8'd0;
            packet[1]   <= 8'd0;
            packet[2]   <= 8'd0;
            packet[3]   <= 8'd0;
            packet[4]   <= 8'd0;
            packet[5]   <= 8'd0;
            packet[6]   <= 8'd0;
            packet[7]   <= 8'd0;
        end else begin
            tx_start   <= 1'b0;
            sent_pulse <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    byte_index <= 3'd0;
                    if (response_valid) begin
                        packet[0] <= SOF0;
                        packet[1] <= SOF1;
                        packet[2] <= status;
                        packet[3] <= sequence_number;
                        packet[4] <= word_address[7:0];
                        packet[5] <= word_address[15:8];
                        packet[6] <= detail;
                        crc_value <= 8'd0;
                        state <= STATE_CRC;
                    end
                end

                STATE_CRC: begin
                    crc_value <= crc8_next(crc_value, packet[byte_index]);
                    if (byte_index == 3'd6) begin
                        packet[7] <= crc8_next(crc_value, packet[byte_index]);
                        byte_index <= 3'd0;
                        state <= STATE_LOAD;
                    end else begin
                        byte_index <= byte_index + 1'b1;
                    end
                end

                STATE_LOAD: begin
                    if (!tx_busy) begin
                        tx_data  <= packet[byte_index];
                        tx_start <= 1'b1;
                        state    <= STATE_WAIT;
                    end
                end

                STATE_WAIT: begin
                    if (tx_done) begin
                        if (byte_index == 3'd7) begin
                            sent_pulse <= 1'b1;
                            state <= STATE_IDLE;
                        end else begin
                            byte_index <= byte_index + 1'b1;
                            state <= STATE_LOAD;
                        end
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end
endmodule
