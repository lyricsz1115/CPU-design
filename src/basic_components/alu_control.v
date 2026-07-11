`include "riscv_defs.vh"

module alu_control(
    input wire [1:0] alu_op,
    input wire [2:0] funct3,
    input wire [6:0] funct7,
    output reg [3:0] alu_ctrl
);
    always @(*) begin
        case (alu_op)
            2'b00: alu_ctrl = `ALU_ADD; // load/store/addi
            2'b01: alu_ctrl = `ALU_SUB; // branch compare
            2'b10: begin
                case (funct3)
                    3'b000: alu_ctrl = (funct7[5]) ? `ALU_SUB : `ALU_ADD;
                    3'b111: alu_ctrl = `ALU_AND;
                    3'b110: alu_ctrl = `ALU_OR;
                    3'b100: alu_ctrl = `ALU_XOR;
                    3'b010: alu_ctrl = `ALU_SLT;
                    default: alu_ctrl = `ALU_NOP;
                endcase
            end
            2'b11: begin
                case (funct3)
                    3'b000: alu_ctrl = `ALU_ADD;
                    3'b111: alu_ctrl = `ALU_AND;
                    3'b110: alu_ctrl = `ALU_OR;
                    3'b100: alu_ctrl = `ALU_XOR;
                    3'b010: alu_ctrl = `ALU_SLT;
                    default: alu_ctrl = `ALU_NOP;
                endcase
            end
            default: alu_ctrl = `ALU_NOP;
        endcase
    end
endmodule
