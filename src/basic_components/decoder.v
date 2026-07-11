module decoder(
    input wire [31:0] inst,
    output wire [6:0] opcode,
    output wire [4:0] rd,
    output wire [2:0] funct3,
    output wire [4:0] rs1,
    output wire [4:0] rs2,
    output wire [6:0] funct7
);
    assign opcode = inst[6:0];
    assign rd = inst[11:7];
    assign funct3 = inst[14:12];
    assign rs1 = inst[19:15];
    assign rs2 = inst[24:20];
    assign funct7 = inst[31:25];
endmodule
/*
31      25 24    20 19    15 14    12 11       7 6         0
┌─────────┬────────┬────────┬────────┬──────────┬──────────┐
│ funct7  │  rs2   │  rs1   │ funct3 │    rd    │  opcode  │
│  7-bit  │ 5-bit  │ 5-bit  │ 3-bit  │  5-bit   │  7-bit   │
└─────────┴────────┴────────┴────────┴──────────┴──────────┘
  inst[31:25] = funct7
  inst[24:20] = rs2
  inst[19:15] = rs1
  inst[14:12] = funct3
  inst[11:7] = rd
  inst[6:0] = opcode
*/
