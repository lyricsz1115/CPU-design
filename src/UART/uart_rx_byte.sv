`timescale 1ns / 1ps

module uart_rx_byte #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BAUD   = 115_200
) (
    input  logic       clk,
    input  logic       reset,
    input  logic       rx,
    output logic [7:0] data,
    output logic       valid,
    output logic       framing_error
);
    localparam integer CLKS_PER_BIT = (CLK_HZ + (BAUD / 2)) / BAUD;
    localparam integer CNT_WIDTH = $clog2(CLKS_PER_BIT + 1);

    localparam logic [1:0] STATE_IDLE  = 2'd0;
    localparam logic [1:0] STATE_START = 2'd1;
    localparam logic [1:0] STATE_DATA  = 2'd2;
    localparam logic [1:0] STATE_STOP  = 2'd3;

    logic [1:0] state;
    logic [CNT_WIDTH-1:0] clk_count;
    logic [2:0] bit_index;
    logic [7:0] rx_shift;
    (* ASYNC_REG = "TRUE" *) logic rx_meta;
    (* ASYNC_REG = "TRUE" *) logic rx_sync;

    always_ff @(posedge clk) begin
        if (reset) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state         <= STATE_IDLE;
            clk_count     <= '0;
            bit_index     <= 3'd0;
            rx_shift      <= 8'd0;
            data          <= 8'd0;
            valid         <= 1'b0;
            framing_error <= 1'b0;
        end else begin
            valid         <= 1'b0;
            framing_error <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    clk_count <= '0;
                    bit_index <= 3'd0;
                    if (!rx_sync) begin
                        clk_count <= CLKS_PER_BIT / 2;
                        state     <= STATE_START;
                    end
                end

                STATE_START: begin
                    if (clk_count != 0) begin
                        clk_count <= clk_count - 1'b1;
                    end else if (!rx_sync) begin
                        clk_count <= CLKS_PER_BIT - 1;
                        state     <= STATE_DATA;
                    end else begin
                        state <= STATE_IDLE;
                    end
                end

                STATE_DATA: begin
                    if (clk_count != 0) begin
                        clk_count <= clk_count - 1'b1;
                    end else begin
                        rx_shift[bit_index] <= rx_sync;
                        clk_count <= CLKS_PER_BIT - 1;
                        if (bit_index == 3'd7) begin
                            bit_index <= 3'd0;
                            state     <= STATE_STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                        end
                    end
                end

                STATE_STOP: begin
                    if (clk_count != 0) begin
                        clk_count <= clk_count - 1'b1;
                    end else begin
                        data <= rx_shift;
                        if (rx_sync) begin
                            valid <= 1'b1;
                        end else begin
                            framing_error <= 1'b1;
                        end
                        state <= STATE_IDLE;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end
endmodule
