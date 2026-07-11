// Branch unit supporting all RV32I conditional branches
// BEQ(000), BNE(001), BLT(100), BGE(101), BLTU(110), BGEU(111)
module branch_unit(
    input wire branch,
    input wire jal,
    input wire zero,
    input wire less_than,            // a < b  signed
    input wire less_than_unsigned,   // a < b  unsigned
    input wire [2:0] funct3,
    output wire pc_src
);
    wire branch_taken;
    assign branch_taken = (funct3 == 3'b000) ? zero :                  // BEQ
                          (funct3 == 3'b001) ? ~zero :                 // BNE
                          (funct3 == 3'b100) ? less_than :             // BLT
                          (funct3 == 3'b101) ? (~less_than | zero) :   // BGE
                          (funct3 == 3'b110) ? less_than_unsigned :    // BLTU
                          (funct3 == 3'b111) ? (~less_than_unsigned | zero) : // BGEU
                          1'b0;

    assign pc_src = jal | (branch & branch_taken);
endmodule
