`timescale 1ns / 1ps

module uart_program_packet_rx #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BYTE_TIMEOUT_US = 2_000
) (
    input  logic        clk,
    input  logic        reset,
    input  logic [7:0]  rx_data,
    input  logic        rx_valid,
    input  logic        rx_framing_error,
    output logic        packet_valid,
    output logic        crc_error,
    output logic        timeout_error,
    output logic [7:0]  command,
    output logic [7:0]  sequence_number,
    output logic [15:0] word_address,
    output logic [31:0] word_data,
    output logic [7:0]  flags
);
    localparam logic [7:0] SOF0 = 8'hAA;
    localparam logic [7:0] SOF1 = 8'h49;
    localparam integer TIMEOUT_CYCLES = (CLK_HZ / 1_000_000) * BYTE_TIMEOUT_US;
    localparam integer TIMEOUT_WIDTH = $clog2(TIMEOUT_CYCLES + 1);

    localparam logic [1:0] STATE_SOF0 = 2'd0;
    localparam logic [1:0] STATE_SOF1 = 2'd1;
    localparam logic [1:0] STATE_BODY = 2'd2;

    logic [1:0] state;
    logic [3:0] byte_index;
    logic [7:0] crc_value;
    logic [TIMEOUT_WIDTH-1:0] timeout_count;

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

    always_ff @(posedge clk) begin
        if (reset) begin
            state          <= STATE_SOF0;
            byte_index     <= 4'd0;
            crc_value      <= 8'd0;
            timeout_count  <= '0;
            packet_valid   <= 1'b0;
            crc_error      <= 1'b0;
            timeout_error  <= 1'b0;
            command        <= 8'd0;
            sequence_number <= 8'd0;
            word_address   <= 16'd0;
            word_data      <= 32'd0;
            flags          <= 8'd0;
        end else begin
            packet_valid  <= 1'b0;
            crc_error     <= 1'b0;
            timeout_error <= 1'b0;

            if (rx_framing_error) begin
                state         <= STATE_SOF0;
                byte_index    <= 4'd0;
                timeout_count <= '0;
            end else if (rx_valid) begin
                timeout_count <= '0;
                case (state)
                    STATE_SOF0: begin
                        if (rx_data == SOF0) begin
                            crc_value <= crc8_next(8'd0, SOF0);
                            state     <= STATE_SOF1;
                        end
                    end

                    STATE_SOF1: begin
                        if (rx_data == SOF1) begin
                            crc_value  <= crc8_next(crc_value, SOF1);
                            byte_index <= 4'd2;
                            state      <= STATE_BODY;
                        end else if (rx_data == SOF0) begin
                            crc_value <= crc8_next(8'd0, SOF0);
                        end else begin
                            state <= STATE_SOF0;
                        end
                    end

                    STATE_BODY: begin
                        if (byte_index < 4'd11) begin
                            crc_value <= crc8_next(crc_value, rx_data);
                            case (byte_index)
                                4'd2: command          <= rx_data;
                                4'd3: sequence_number  <= rx_data;
                                4'd4: word_address[7:0]  <= rx_data;
                                4'd5: word_address[15:8] <= rx_data;
                                4'd6: word_data[7:0]     <= rx_data;
                                4'd7: word_data[15:8]    <= rx_data;
                                4'd8: word_data[23:16]   <= rx_data;
                                4'd9: word_data[31:24]   <= rx_data;
                                4'd10: flags           <= rx_data;
                                default: begin end
                            endcase
                            byte_index <= byte_index + 1'b1;
                        end else begin
                            if (rx_data == crc_value)
                                packet_valid <= 1'b1;
                            else
                                crc_error <= 1'b1;
                            state      <= STATE_SOF0;
                            byte_index <= 4'd0;
                        end
                    end

                    default: state <= STATE_SOF0;
                endcase
            end else if (state != STATE_SOF0) begin
                if (timeout_count >= TIMEOUT_CYCLES - 1) begin
                    state         <= STATE_SOF0;
                    byte_index    <= 4'd0;
                    timeout_count <= '0;
                    timeout_error <= 1'b1;
                end else begin
                    timeout_count <= timeout_count + 1'b1;
                end
            end else begin
                timeout_count <= '0;
            end
        end
    end
endmodule
