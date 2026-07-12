`ifndef RISCV_DEFS_VH
`define RISCV_DEFS_VH

`define OPCODE_RTYPE  7'b0110011
`define OPCODE_ITYPE  7'b0010011
`define OPCODE_LOAD   7'b0000011
`define OPCODE_STORE  7'b0100011
`define OPCODE_BRANCH 7'b1100011
`define OPCODE_JAL    7'b1101111
`define OPCODE_LUI    7'b0110111

// Base RV32I ALU operations
`define ALU_ADD   4'b0000
`define ALU_SUB   4'b0001
`define ALU_AND   4'b0010
`define ALU_OR    4'b0011
`define ALU_XOR   4'b0100
`define ALU_SLT   4'b0101
`define ALU_SLTU  4'b0110
`define ALU_SLL   4'b0111
`define ALU_SRL   4'b1000
`define ALU_SRA   4'b1001
// RV32M multiply (single-cycle, alu.v)
`define ALU_MUL      4'b1010
`define ALU_MULH     4'b1011
`define ALU_MULHSU   4'b1100
`define ALU_MULHU    4'b1101
// RV32M divide / remainder (multi-cycle, div_unit.v)
`define ALU_DIV      4'b1110
`define ALU_DIVU     4'b1110
`define ALU_REM      4'b1110
`define ALU_REMU     4'b1110
`define ALU_NOP      4'b1111

// ── SYSTEM opcode (CSR / ECALL / MRET) ──
`define OPCODE_SYSTEM  7'b1110011

// ── CSR addresses ──
`define CSR_MSTATUS  12'h300
`define CSR_MTVEC    12'h305
`define CSR_MEPC     12'h341
`define CSR_MCAUSE   12'h342
`define CSR_MIE      12'h304
`define CSR_MIP      12'h344

// ── mcause encodings ──
`define MCAUSE_MTIP   32'h80000007
`define MCAUSE_MEIP   32'h8000000B
`define MCAUSE_MSIP   32'h80000003
`define MCAUSE_ECALL  32'h0000000B

// M-extension funct7 marker (bit0 distinguishes from base RV32I)
`define FUNCT7_MEXT  7'b0000001

`endif
