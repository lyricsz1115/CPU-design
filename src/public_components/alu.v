`include "riscv_defs.vh"

module alu(
    input wire [31:0] a,
    input wire [31:0] b,
    input wire [3:0] alu_ctrl,
    output reg [31:0] y,
    output wire zero
);
    always @(*) begin
        case (alu_ctrl)
            `ALU_ADD: y = a + b;
            `ALU_SUB: y = a - b;
            `ALU_AND: y = a & b;
            `ALU_OR:  y = a | b;
            `ALU_XOR: y = a ^ b;
            `ALU_SLT: y = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            default:  y = 32'b0;
        endcase
    end

    assign zero = (y == 32'b0);
endmodule
