`include "riscv_defs.vh"

module alu(
    input wire [31:0] a,
    input wire [31:0] b,
    input wire [3:0] alu_ctrl,
    output reg [31:0] y,
    output wire zero,
    output wire less_than,           // a < b  (signed)   — for BLT/BGE
    output wire less_than_unsigned   // a < b  (unsigned) — for BLTU/BGEU
);
    // Branch-comparison signals (always computed from operands)
    assign less_than          = $signed(a) < $signed(b);
    assign less_than_unsigned = a < b;
    assign zero               = (y == 32'b0);

    // 64-bit intermediate for MULH / MULHSU / MULHU
    wire [63:0] mul_signed   = $signed(a) * $signed(b);
    wire [63:0] mul_signed_u = $signed(a) * $unsigned(b);
    wire [63:0] mul_unsigned = a * b;

    always @(*) begin
        case (alu_ctrl)
            `ALU_ADD:    y = a + b;
            `ALU_SUB:    y = a - b;
            `ALU_AND:    y = a & b;
            `ALU_OR:     y = a | b;
            `ALU_XOR:    y = a ^ b;
            `ALU_SLT:    y = less_than          ? 32'd1 : 32'd0;
            `ALU_SLTU:   y = less_than_unsigned ? 32'd1 : 32'd0;
            `ALU_SLL:    y = a << b[4:0];
            `ALU_SRL:    y = a >> b[4:0];
            `ALU_SRA:    y = $signed(a) >>> b[4:0];
            `ALU_MUL:    y = a * b;              // lower 32 bits
            `ALU_MULH:   y = mul_signed[63:32];
            `ALU_MULHSU: y = mul_signed_u[63:32];
            `ALU_MULHU:  y = mul_unsigned[63:32];
            // Single-cycle div/rem fallback (simulation / single-cycle CPU)
            `ALU_DIV, `ALU_DIVU, `ALU_REM, `ALU_REMU: begin
                // Divide-by-zero and overflow handling per RISC-V spec
                if (b == 32'b0) begin
                    y = (alu_ctrl == `ALU_REM || alu_ctrl == `ALU_REMU) ? a : 32'hffffffff;
                end else if (alu_ctrl == `ALU_DIV && a == 32'h80000000 && b == 32'hffffffff) begin
                    y = 32'h80000000;   // signed overflow
                end else begin
                    case (alu_ctrl)
                        `ALU_DIV:  y = $signed($signed(a) / $signed(b));
                        `ALU_DIVU: y = a / b;
                        `ALU_REM:  y = (a == 32'h80000000 && b == 32'hffffffff)
                                       ? 32'd0 : $signed($signed(a) % $signed(b));
                        `ALU_REMU: y = a % b;
                    endcase
                end
            end
            default:     y = 32'b0;
        endcase
    end
endmodule
