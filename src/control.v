`include "riscv_defs.vh"

module control(
    input wire [6:0] opcode,
    output reg branch,
    output reg jal,
    output reg mem_read,
    output reg mem_to_reg,
    output reg [1:0] alu_op,
    output reg mem_write,
    output reg alu_src,
    output reg reg_write
);
    always @(*) begin
        branch = 1'b0;
        jal = 1'b0;
        mem_read = 1'b0;
        mem_to_reg = 1'b0;
        alu_op = 2'b00;
        mem_write = 1'b0;
        alu_src = 1'b0;
        reg_write = 1'b0;

        case (opcode)
            `OPCODE_RTYPE: begin
                alu_op = 2'b10;
                reg_write = 1'b1;
            end
            `OPCODE_ITYPE: begin
                alu_src = 1'b1;
                alu_op = 2'b00;
                reg_write = 1'b1;
            end
            `OPCODE_LOAD: begin
                alu_src = 1'b1;
                mem_read = 1'b1;
                mem_to_reg = 1'b1;
                reg_write = 1'b1;
            end
            `OPCODE_STORE: begin
                alu_src = 1'b1;
                mem_write = 1'b1;
            end
            `OPCODE_BRANCH: begin
                branch = 1'b1;
                alu_op = 2'b01;
            end
            `OPCODE_JAL: begin
                jal = 1'b1;
                reg_write = 1'b1;
            end
        endcase
    end
endmodule
