module seg7_hex_display #(
    parameter SCAN_DIVIDER_BITS = 16
)(
    input wire clk,
    input wire rst,
    input wire [31:0] value,
    output reg [7:0] seg_an,
    output reg [7:0] seg_out
);
    reg [SCAN_DIVIDER_BITS-1:0] scan_counter;
    wire [2:0] digit_index = scan_counter[SCAN_DIVIDER_BITS-1:SCAN_DIVIDER_BITS-3];
    reg [3:0] digit_value;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            scan_counter <= {SCAN_DIVIDER_BITS{1'b0}};
        end else begin
            scan_counter <= scan_counter + {{(SCAN_DIVIDER_BITS-1){1'b0}}, 1'b1};
        end
    end

    always @(*) begin
        case (digit_index)
            3'd0: begin seg_an = 8'b11111110; digit_value = value[3:0]; end
            3'd1: begin seg_an = 8'b11111101; digit_value = value[7:4]; end
            3'd2: begin seg_an = 8'b11111011; digit_value = value[11:8]; end
            3'd3: begin seg_an = 8'b11110111; digit_value = value[15:12]; end
            3'd4: begin seg_an = 8'b11101111; digit_value = value[19:16]; end
            3'd5: begin seg_an = 8'b11011111; digit_value = value[23:20]; end
            3'd6: begin seg_an = 8'b10111111; digit_value = value[27:24]; end
            default: begin seg_an = 8'b01111111; digit_value = value[31:28]; end
        endcase

        case (digit_value)
            4'h0: seg_out = 8'b01000000;
            4'h1: seg_out = 8'b01111001;
            4'h2: seg_out = 8'b00100100;
            4'h3: seg_out = 8'b00110000;
            4'h4: seg_out = 8'b00011001;
            4'h5: seg_out = 8'b00010010;
            4'h6: seg_out = 8'b00000010;
            4'h7: seg_out = 8'b01111000;
            4'h8: seg_out = 8'b00000000;
            4'h9: seg_out = 8'b00010000;
            4'ha: seg_out = 8'b00001000;
            4'hb: seg_out = 8'b00000011;
            4'hc: seg_out = 8'b01000110;
            4'hd: seg_out = 8'b00100001;
            4'he: seg_out = 8'b00000110;
            4'hf: seg_out = 8'b00001110;
            default: seg_out = 8'b11111111;
        endcase
    end
endmodule
