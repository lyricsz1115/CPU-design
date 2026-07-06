module cpu_top #(
    parameter INIT_FILE = "program/sum.mem"
)(
    input wire clk,
    input wire rst,
    output wire [31:0] debug_pc,
    output wire [31:0] debug_dmem0
);
    wire [31:0] pc_value;
    wire [31:0] inst;
    wire [6:0] opcode;
    wire [4:0] rd;
    wire [2:0] funct3;
    wire [4:0] rs1;
    wire [4:0] rs2;
    wire [6:0] funct7;
    wire branch;
    wire jal;
    wire mem_read;
    wire mem_to_reg;
    wire [1:0] alu_op;
    wire mem_write;
    wire alu_src;
    wire reg_write;
    wire [31:0] imm;
    wire [31:0] reg_data1;
    wire [31:0] reg_data2;
    wire [3:0] alu_ctrl;
    wire [31:0] alu_b;
    wire [31:0] alu_y;
    wire zero;
    wire [31:0] mem_data;
    wire [31:0] wb_data;
    wire pc_src;
    wire [31:0] pc_plus4 = pc_value + 32'd4;
    wire [31:0] branch_target = pc_value + imm;
    wire [31:0] next_pc = pc_src ? branch_target : pc_plus4;

    pc u_pc(.clk(clk), .rst(rst), .en(1'b1), .next_pc(next_pc), .pc(pc_value));
    imem #(.INIT_FILE(INIT_FILE)) u_imem(.addr(pc_value), .inst(inst));
    decoder u_decoder(.inst(inst), .opcode(opcode), .rd(rd), .funct3(funct3), .rs1(rs1), .rs2(rs2), .funct7(funct7));
    control u_control(.opcode(opcode), .branch(branch), .jal(jal), .mem_read(mem_read), .mem_to_reg(mem_to_reg), .alu_op(alu_op), .mem_write(mem_write), .alu_src(alu_src), .reg_write(reg_write));
    imm_gen u_imm_gen(.inst(inst), .imm(imm));
    regfile u_regfile(.clk(clk), .rst(rst), .reg_write(reg_write), .rs1(rs1), .rs2(rs2), .rd(rd), .write_data(wb_data), .read_data1(reg_data1), .read_data2(reg_data2));
    alu_control u_alu_control(.alu_op(alu_op), .funct3(funct3), .funct7(funct7), .alu_ctrl(alu_ctrl));
    assign alu_b = alu_src ? imm : reg_data2;
    alu u_alu(.a(reg_data1), .b(alu_b), .alu_ctrl(alu_ctrl), .y(alu_y), .zero(zero));
    dmem u_dmem(.clk(clk), .mem_read(mem_read), .mem_write(mem_write), .addr(alu_y), .write_data(reg_data2), .read_data(mem_data));
    assign wb_data = jal ? pc_plus4 : (mem_to_reg ? mem_data : alu_y);
    branch_unit u_branch_unit(.branch(branch), .jal(jal), .zero(zero), .pc_src(pc_src));

    assign debug_pc = pc_value;
    assign debug_dmem0 = u_dmem.mem[0];
endmodule
