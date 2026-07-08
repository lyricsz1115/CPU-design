module pipeline_cpu_top #(
    parameter INIT_FILE = "sum.mem",
    parameter USE_INIT_FILE = 1,
    parameter PROGRAM_ID = 0
)(
    input wire clk,
    input wire rst,
    output wire stall_debug,
    output wire flush_debug,
    output wire inst_valid_debug,
    output wire [31:0] debug_cycle_count,
    output wire [31:0] debug_instret_count,
    output wire [31:0] debug_stall_count,
    output wire [31:0] debug_flush_count,
    output wire [31:0] debug_pc,
    output wire [31:0] debug_dmem0,
    output wire [31:0] debug_dmem1
);
    wire [31:0] pc_value;
    wire [31:0] pc_plus4_if = pc_value + 32'd4;
    wire [31:0] inst_if;
    wire [31:0] next_pc;

    wire [31:0] if_id_pc;
    wire [31:0] if_id_inst;
    wire [6:0] id_opcode;
    wire [4:0] id_rd;
    wire [2:0] id_funct3;
    wire [4:0] id_rs1;
    wire [4:0] id_rs2;
    wire [6:0] id_funct7;
    wire id_branch;
    wire id_jal;
    wire id_mem_read;
    wire id_mem_to_reg;
    wire [1:0] id_alu_op;
    wire id_mem_write;
    wire id_alu_src;
    wire id_alu_a_zero;
    wire id_reg_write;
    wire [31:0] id_imm;
    wire [31:0] id_reg_data1;
    wire [31:0] id_reg_data2;
    wire [31:0] id_reg_data1_bypass;
    wire [31:0] id_reg_data2_bypass;

    wire ex_reg_write;
    wire ex_mem_to_reg;
    wire ex_mem_read;
    wire ex_mem_write;
    wire ex_branch;
    wire ex_jal;
    wire ex_alu_src;
    wire [1:0] ex_alu_op;
    wire [31:0] ex_pc;
    wire [31:0] ex_reg_data1;
    wire [31:0] ex_reg_data2;
    wire [31:0] ex_imm;
    wire [4:0] ex_rs1;
    wire [4:0] ex_rs2;
    wire [4:0] ex_rd;
    wire [2:0] ex_funct3;
    wire [6:0] ex_funct7;
    wire [3:0] ex_alu_ctrl;
    wire [1:0] forward_a;
    wire [1:0] forward_b;
    wire [31:0] forward_a_data;
    wire [31:0] forward_b_data;
    wire [31:0] ex_alu_b;
    wire [31:0] ex_alu_result;
    wire ex_zero;
    wire ex_pc_src;
    wire [31:0] ex_branch_target = ex_pc + ex_imm;
    wire [31:0] ex_pc_plus4 = ex_pc + 32'd4;

    wire mem_reg_write;
    wire mem_mem_to_reg;
    wire mem_mem_read;
    wire mem_mem_write;
    wire mem_jal;
    wire [31:0] mem_pc_plus4;
    wire [31:0] mem_alu_result;
    wire [31:0] mem_write_data;
    wire [4:0] mem_rd;
    wire [31:0] mem_read_data;

    wire wb_reg_write;
    wire wb_mem_to_reg;
    wire wb_jal;
    wire [31:0] wb_pc_plus4;
    wire [31:0] wb_mem_data;
    wire [31:0] wb_alu_result;
    wire [4:0] wb_rd;
    wire [31:0] wb_data;

    wire pc_write;
    wire if_id_write;
    wire if_id_flush;
    wire id_ex_flush;
    wire load_use_stall;
    wire inst_valid_wb;
    reg if_id_valid;
    reg id_ex_valid;
    reg ex_mem_valid;
    reg mem_wb_valid;

    assign next_pc = ex_pc_src ? ex_branch_target : pc_plus4_if;

    pc u_pc(.clk(clk), .rst(rst), .en(pc_write), .next_pc(next_pc), .pc(pc_value));
    imem #(.INIT_FILE(INIT_FILE), .USE_INIT_FILE(USE_INIT_FILE), .PROGRAM_ID(PROGRAM_ID)) u_imem(.addr(pc_value), .inst(inst_if));

    if_id_reg u_if_id(
        .clk(clk), .rst(rst), .en(if_id_write), .flush(if_id_flush),
        .pc_in(pc_value), .inst_in(inst_if), .pc_out(if_id_pc), .inst_out(if_id_inst)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            if_id_valid <= 1'b0;
        end else if (if_id_flush) begin
            if_id_valid <= 1'b0;
        end else if (if_id_write) begin
            if_id_valid <= 1'b1;
        end
    end

    decoder u_decoder(.inst(if_id_inst), .opcode(id_opcode), .rd(id_rd), .funct3(id_funct3), .rs1(id_rs1), .rs2(id_rs2), .funct7(id_funct7));
    control u_control(.opcode(id_opcode), .branch(id_branch), .jal(id_jal), .mem_read(id_mem_read), .mem_to_reg(id_mem_to_reg), .alu_op(id_alu_op), .mem_write(id_mem_write), .alu_src(id_alu_src), .alu_a_zero(id_alu_a_zero), .reg_write(id_reg_write));
    imm_gen u_imm_gen(.inst(if_id_inst), .imm(id_imm));
    regfile u_regfile(.clk(clk), .rst(rst), .reg_write(wb_reg_write), .rs1(id_rs1), .rs2(id_rs2), .rd(wb_rd), .write_data(wb_data), .read_data1(id_reg_data1), .read_data2(id_reg_data2));
    assign id_reg_data1_bypass = (wb_reg_write && wb_rd != 5'b0 && wb_rd == id_rs1) ? wb_data : id_reg_data1;
    assign id_reg_data2_bypass = (wb_reg_write && wb_rd != 5'b0 && wb_rd == id_rs2) ? wb_data : id_reg_data2;

    hazard_unit u_hazard(
        .id_ex_mem_read(ex_mem_read), .id_ex_rd(ex_rd), .if_id_rs1(id_rs1), .if_id_rs2(id_rs2), .pc_src(ex_pc_src),
        .pc_write(pc_write), .if_id_write(if_id_write), .if_id_flush(if_id_flush), .id_ex_flush(id_ex_flush)
    );
    assign load_use_stall = ~pc_write;

    id_ex_reg u_id_ex(
        .clk(clk), .rst(rst), .flush(id_ex_flush),
        .reg_write_in(id_reg_write), .mem_to_reg_in(id_mem_to_reg), .mem_read_in(id_mem_read), .mem_write_in(id_mem_write),
        .branch_in(id_branch), .jal_in(id_jal), .alu_src_in(id_alu_src), .alu_op_in(id_alu_op),
        .pc_in(if_id_pc), .reg_data1_in(id_reg_data1_bypass), .reg_data2_in(id_reg_data2_bypass), .imm_in(id_imm),
        .rs1_in(id_rs1), .rs2_in(id_rs2), .rd_in(id_rd), .funct3_in(id_funct3), .funct7_in(id_funct7),
        .reg_write_out(ex_reg_write), .mem_to_reg_out(ex_mem_to_reg), .mem_read_out(ex_mem_read), .mem_write_out(ex_mem_write),
        .branch_out(ex_branch), .jal_out(ex_jal), .alu_src_out(ex_alu_src), .alu_op_out(ex_alu_op),
        .pc_out(ex_pc), .reg_data1_out(ex_reg_data1), .reg_data2_out(ex_reg_data2), .imm_out(ex_imm),
        .rs1_out(ex_rs1), .rs2_out(ex_rs2), .rd_out(ex_rd), .funct3_out(ex_funct3), .funct7_out(ex_funct7)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            id_ex_valid <= 1'b0;
        end else if (id_ex_flush) begin
            id_ex_valid <= 1'b0;
        end else begin
            id_ex_valid <= if_id_valid;
        end
    end

    forwarding_unit u_forwarding(
        .ex_mem_reg_write(mem_reg_write), .ex_mem_rd(mem_rd), .mem_wb_reg_write(wb_reg_write), .mem_wb_rd(wb_rd),
        .id_ex_rs1(ex_rs1), .id_ex_rs2(ex_rs2), .forward_a(forward_a), .forward_b(forward_b)
    );

    assign forward_a_data = (forward_a == 2'b10) ? mem_alu_result :
                            (forward_a == 2'b01) ? wb_data : ex_reg_data1;
    assign forward_b_data = (forward_b == 2'b10) ? mem_alu_result :
                            (forward_b == 2'b01) ? wb_data : ex_reg_data2;

    alu_control u_alu_control(.alu_op(ex_alu_op), .funct3(ex_funct3), .funct7(ex_funct7), .alu_ctrl(ex_alu_ctrl));
    assign ex_alu_b = ex_alu_src ? ex_imm : forward_b_data;
    alu u_alu(.a(forward_a_data), .b(ex_alu_b), .alu_ctrl(ex_alu_ctrl), .y(ex_alu_result), .zero(ex_zero));
    branch_unit u_branch_unit(.branch(ex_branch), .jal(ex_jal), .zero(ex_zero), .pc_src(ex_pc_src));

    ex_mem_reg u_ex_mem(
        .clk(clk), .rst(rst),
        .reg_write_in(ex_reg_write), .mem_to_reg_in(ex_mem_to_reg), .mem_read_in(ex_mem_read), .mem_write_in(ex_mem_write),
        .jal_in(ex_jal), .pc_plus4_in(ex_pc_plus4), .alu_result_in(ex_alu_result), .write_data_in(forward_b_data), .rd_in(ex_rd),
        .reg_write_out(mem_reg_write), .mem_to_reg_out(mem_mem_to_reg), .mem_read_out(mem_mem_read), .mem_write_out(mem_mem_write),
        .jal_out(mem_jal), .pc_plus4_out(mem_pc_plus4), .alu_result_out(mem_alu_result), .write_data_out(mem_write_data), .rd_out(mem_rd)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ex_mem_valid <= 1'b0;
        end else begin
            ex_mem_valid <= id_ex_valid;
        end
    end

    dmem u_dmem(.clk(clk), .mem_read(mem_mem_read), .mem_write(mem_mem_write), .addr(mem_alu_result), .write_data(mem_write_data), .read_data(mem_read_data));

    mem_wb_reg u_mem_wb(
        .clk(clk), .rst(rst),
        .reg_write_in(mem_reg_write), .mem_to_reg_in(mem_mem_to_reg), .jal_in(mem_jal),
        .pc_plus4_in(mem_pc_plus4), .mem_data_in(mem_read_data), .alu_result_in(mem_alu_result), .rd_in(mem_rd),
        .reg_write_out(wb_reg_write), .mem_to_reg_out(wb_mem_to_reg), .jal_out(wb_jal),
        .pc_plus4_out(wb_pc_plus4), .mem_data_out(wb_mem_data), .alu_result_out(wb_alu_result), .rd_out(wb_rd)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_wb_valid <= 1'b0;
        end else begin
            mem_wb_valid <= ex_mem_valid;
        end
    end

    assign wb_data = wb_jal ? wb_pc_plus4 : (wb_mem_to_reg ? wb_mem_data : wb_alu_result);

    assign inst_valid_wb = mem_wb_valid;

    perf_counter u_perf_counter(
        .clk(clk),
        .rst(rst),
        .inst_valid(inst_valid_wb),
        .stall(load_use_stall),
        .flush(ex_pc_src),
        .cycle_count(debug_cycle_count),
        .instret_count(debug_instret_count),
        .stall_count(debug_stall_count),
        .flush_count(debug_flush_count)
    );

    assign stall_debug = load_use_stall;
    assign flush_debug = ex_pc_src;
    assign inst_valid_debug = inst_valid_wb;
    assign debug_pc = pc_value;
    assign debug_dmem0 = u_dmem.mem[0];
    assign debug_dmem1 = u_dmem.mem[1];
endmodule
