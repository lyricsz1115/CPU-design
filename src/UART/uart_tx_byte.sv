`timescale 1ns / 1ps

module uart_tx_byte #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BAUD   = 115_200
) (
    input  logic       clk,
    input  logic       reset,
    input  logic [7:0] data,
    input  logic       start,
    output logic       tx,
    output logic       busy,
    output logic       done
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
    logic [7:0] tx_shift;

    always_ff @(posedge clk) begin
        if (reset) begin
            state     <= STATE_IDLE;
            clk_count <= '0;
            bit_index <= 3'd0;
            tx_shift  <= 8'd0;
            tx        <= 1'b1;
            busy      <= 1'b0;
            done      <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    tx        <= 1'b1;
                    busy      <= 1'b0;
                    clk_count <= '0;
                    bit_index <= 3'd0;
                    if (start) begin
                        tx_shift  <= data;
                        tx        <= 1'b0;
                        busy      <= 1'b1;
                        clk_count <= CLKS_PER_BIT - 1;
                        state     <= STATE_START;
                    end
                end

                STATE_START: begin
                    busy <= 1'b1;
                    if (clk_count != 0) begin
                        clk_count <= clk_count - 1'b1;
                    end else begin
                        tx        <= tx_shift[0];
                        clk_count <= CLKS_PER_BIT - 1;
                        state     <= STATE_DATA;
                    end
                end

                STATE_DATA: begin
                    busy <= 1'b1;
                    if (clk_count != 0) begin
                        clk_count <= clk_count - 1'b1;
                    end else if (bit_index == 3'd7) begin
                        tx        <= 1'b1;
                        bit_index <= 3'd0;
                        clk_count <= CLKS_PER_BIT - 1;
                        state     <= STATE_STOP;
                    end else begin
                        bit_index <= bit_index + 1'b1;
                        tx        <= tx_shift[bit_index + 1'b1];
                        clk_count <= CLKS_PER_BIT - 1;
                    end
                end

                STATE_STOP: begin
                    busy <= 1'b1;
                    if (clk_count != 0) begin
                        clk_count <= clk_count - 1'b1;
                    end else begin
                        tx    <= 1'b1;
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        state <= STATE_IDLE;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end
endmodule
