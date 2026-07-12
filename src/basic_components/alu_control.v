`include "riscv_defs.vh"

// ALU Control Unit
// alu_op=00: load/store/lui → ADD (address calc / pass-through)
// alu_op=01: branch         → SUB (compare for zero / sign / carry)
// alu_op=10: R-type         → funct3 + funct7 full decode (base RV32I + M-ext)
// alu_op=11: I-type ALU     → funct3 decode (no funct7[5] ADD/SUB trap)
module alu_control(
    input wire [1:0] alu_op,
    input wire [2:0] funct3,
    input wire [6:0] funct7,
    output reg [3:0] alu_ctrl
);
    always @(*) begin
        case (alu_op)
            2'b00: alu_ctrl = `ALU_ADD;   // load / store / lui

            2'b01: alu_ctrl = `ALU_SUB;   // branch: a - b → zero + sign

            2'b10: begin                  // R-type (includes M-extension)
                if (funct7[0]) begin       // M-extension: funct7 = 7'b0000001
                    case (funct3)
                        3'b000: alu_ctrl = `ALU_MUL;
                        3'b001: alu_ctrl = `ALU_MULH;
                        3'b010: alu_ctrl = `ALU_MULHSU;
                        3'b011: alu_ctrl = `ALU_MULHU;
                        3'b100: alu_ctrl = `ALU_DIV;
                        3'b101: alu_ctrl = `ALU_DIVU;
                        3'b110: alu_ctrl = `ALU_REM;
                        3'b111: alu_ctrl = `ALU_REMU;
                        default: alu_ctrl = `ALU_NOP;
                    endcase
                end else begin            // base RV32I R-type
                    case (funct3)
                        3'b000: alu_ctrl = (funct7[5]) ? `ALU_SUB : `ALU_ADD;
                        3'b001: alu_ctrl = `ALU_SLL;
                        3'b010: alu_ctrl = `ALU_SLT;
                        3'b011: alu_ctrl = `ALU_SLTU;
                        3'b100: alu_ctrl = `ALU_XOR;
                        3'b101: alu_ctrl = (funct7[5]) ? `ALU_SRA : `ALU_SRL;
                        3'b110: alu_ctrl = `ALU_OR;
                        3'b111: alu_ctrl = `ALU_AND;
                        default: alu_ctrl = `ALU_NOP;
                    endcase
                end
            end

            2'b11: begin                  // I-type ALU (funct3 only; no funct7[5] ADD/SUB trap)
                case (funct3)
                    3'b000: alu_ctrl = `ALU_ADD;   // ADDI
                    3'b001: alu_ctrl = `ALU_SLL;   // SLLI
                    3'b010: alu_ctrl = `ALU_SLT;   // SLTI
                    3'b011: alu_ctrl = `ALU_SLTU;  // SLTIU
                    3'b100: alu_ctrl = `ALU_XOR;   // XORI
                    3'b101: alu_ctrl = (funct7[5]) ? `ALU_SRA : `ALU_SRL;  // SRAI / SRLI
                    3'b110: alu_ctrl = `ALU_OR;    // ORI
                    3'b111: alu_ctrl = `ALU_AND;   // ANDI
                    default: alu_ctrl = `ALU_NOP;
                endcase
            end
            default: alu_ctrl = `ALU_NOP;
        endcase
    end
endmodule
