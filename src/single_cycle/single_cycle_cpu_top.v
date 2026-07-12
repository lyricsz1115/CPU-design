module cpu_top #(
    parameter INIT_FILE = "sum.mem",
    parameter USE_INIT_FILE = 1,
    parameter PROGRAM_ID = 0,
    parameter USE_EXTERNAL_DATA_BUS = 0
)(
    input wire clk,
    input wire rst,
    input wire imem_write_enable,
    input wire [31:0] imem_write_addr,
    input wire [31:0] imem_write_data,
    input wire [31:0] external_read_data,
    output wire external_mem_read,
    output wire external_mem_write,
    output wire [31:0] external_addr,
    output wire [31:0] external_write_data,
    output wire inst_valid,
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
    wire alu_a_zero;
    wire reg_write;
    wire [31:0] imm;
    wire [31:0] reg_data1;
    wire [31:0] reg_data2;
    wire [3:0] alu_ctrl;
    wire [31:0] alu_a;
    wire [31:0] alu_b;
    wire [31:0] alu_y;
    wire zero;
    wire less_than;
    wire less_than_unsigned;
    wire [31:0] internal_mem_data;
    wire [31:0] mem_data;
    wire [31:0] wb_data;
    wire pc_src;
    wire [31:0] pc_plus4 = pc_value + 32'd4;
    wire [31:0] branch_target = pc_value + imm;
    wire [31:0] next_pc = pc_src ? branch_target : pc_plus4;

    pc u_pc(.clk(clk), .rst(rst), .en(1'b1), .next_pc(next_pc), .pc(pc_value));
    imem #(.INIT_FILE(INIT_FILE), .USE_INIT_FILE(USE_INIT_FILE), .PROGRAM_ID(PROGRAM_ID)) u_imem(
        .addr(pc_value),
        .clk(clk),
        .write_enable(imem_write_enable),
        .write_addr(imem_write_addr),
        .write_data(imem_write_data),
        .debug_index(8'b0),
        .inst(inst),
        .debug_data()
    );
    decoder u_decoder(.inst(inst), .opcode(opcode), .rd(rd), .funct3(funct3), .rs1(rs1), .rs2(rs2), .funct7(funct7));
    control u_control(.opcode(opcode), .branch(branch), .jal(jal), .mem_read(mem_read), .mem_to_reg(mem_to_reg), .alu_op(alu_op), .mem_write(mem_write), .alu_src(alu_src), .alu_a_zero(alu_a_zero), .reg_write(reg_write));
    imm_gen u_imm_gen(.inst(inst), .imm(imm));
    regfile u_regfile(.clk(clk), .rst(rst), .reg_write(reg_write), .rs1(rs1), .rs2(rs2), .rd(rd), .write_data(wb_data), .debug_index(5'b0), .read_data1(reg_data1), .read_data2(reg_data2), .debug_data());
    alu_control u_alu_control(.alu_op(alu_op), .funct3(funct3), .funct7(funct7), .alu_ctrl(alu_ctrl));
    assign alu_a = alu_a_zero ? 32'b0 : reg_data1;
    assign alu_b = alu_src ? imm : reg_data2;
    alu u_alu(.a(alu_a), .b(alu_b), .alu_ctrl(alu_ctrl), .y(alu_y), .zero(zero),
              .less_than(less_than), .less_than_unsigned(less_than_unsigned));
    dmem u_dmem(
        .clk(clk),
        .mem_read(mem_read && !USE_EXTERNAL_DATA_BUS),
        .mem_write(mem_write && !USE_EXTERNAL_DATA_BUS),
        .addr(alu_y),
        .write_data(reg_data2),
        .read_data(internal_mem_data)
    );
    assign mem_data = USE_EXTERNAL_DATA_BUS ? external_read_data : internal_mem_data;
    assign wb_data = jal ? pc_plus4 : (mem_to_reg ? mem_data : alu_y);
    branch_unit u_branch_unit(.branch(branch), .jal(jal), .zero(zero),
                              .less_than(less_than), .less_than_unsigned(less_than_unsigned),
                              .funct3(funct3), .pc_src(pc_src));

    assign external_mem_read = USE_EXTERNAL_DATA_BUS ? mem_read : 1'b0;
    assign external_mem_write = USE_EXTERNAL_DATA_BUS ? mem_write : 1'b0;
    assign external_addr = alu_y;
    assign external_write_data = reg_data2;
    assign inst_valid = 1'b1;
    assign debug_pc = pc_value;
    assign debug_dmem0 = USE_EXTERNAL_DATA_BUS ? 32'b0 : u_dmem.mem[0];
endmodule
