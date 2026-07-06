`include "riscv_defs.vh"

module imm_gen(
    input wire [31:0] inst,
    output reg [31:0] imm
);
    wire [6:0] opcode = inst[6:0];

    always @(*) begin
        case (opcode)
            `OPCODE_ITYPE,
            `OPCODE_LOAD: begin
                imm = {{20{inst[31]}}, inst[31:20]};
            end
            `OPCODE_STORE: begin
                imm = {{20{inst[31]}}, inst[31:25], inst[11:7]};
            end
            `OPCODE_BRANCH: begin
                imm = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
            end
            `OPCODE_JAL: begin
                imm = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
            end
            default: begin
                imm = 32'b0;
            end
        endcase
    end
endmodule
