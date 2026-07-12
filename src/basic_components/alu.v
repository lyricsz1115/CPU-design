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

    // BUG #6 fix: Single shared 64-bit multiplier with operand conditioning.
    // Three parallel 32×32→64 multipliers (signed, signed×unsigned, unsigned)
    // created ~12ns combinational path through the final MUX tree
    // (WNS = -11.904 ns on 10 ns clock).  Replace with ONE signed multiplier
    // whose operands are sign/zero-extended based on the MUL variant.
    //
    //  Variant   mul_a_64                 mul_b_64
    //  MUL       sign-extended            sign-extended
    //  MULH      sign-extended            sign-extended
    //  MULHSU    sign-extended            zero-extended
    //  MULHU     zero-extended            zero-extended
    wire signed [63:0] mul_a_s = (alu_ctrl == `ALU_MULHU)
                                 ? $signed({32'd0, a})
                                 : $signed({{32{a[31]}}, a});
    wire signed [63:0] mul_b_s = (alu_ctrl == `ALU_MULHSU || alu_ctrl == `ALU_MULHU)
                                 ? $signed({32'd0, b})
                                 : $signed({{32{b[31]}}, b});
    wire signed [63:0] mul_result_s = mul_a_s * mul_b_s;

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
            `ALU_MUL:    y = mul_result_s[31:0];
            `ALU_MULH:   y = mul_result_s[63:32];
            `ALU_MULHSU: y = mul_result_s[63:32];
            `ALU_MULHU:  y = mul_result_s[63:32];
            // BUG #3 fix: Dead value to prevent Vivado from inferring a
            // 32-bit combinational divider (~30-50 ns, violates 10 ns timing).
            // Pipeline CPU uses div_unit.v (multi-cycle FSM) for DIV/REM;
            // single-cycle CPU does NOT support division with this change.
            `ALU_DIV, `ALU_DIVU, `ALU_REM, `ALU_REMU: begin
                y = 32'b0;
            end
            default:     y = 32'b0;
        endcase
    end
endmodule
