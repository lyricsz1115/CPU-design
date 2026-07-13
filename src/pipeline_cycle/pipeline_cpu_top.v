`include "riscv_defs.vh"
module pipeline_cpu_top #(
    parameter INIT_FILE = "sum.mem",
    parameter USE_INIT_FILE = 1,
    parameter PROGRAM_ID = 0,
    parameter ENABLE_IMEM_WRITE = 0,
    parameter USE_EXTERNAL_DATA_BUS = 0,
    parameter ENABLE_DATA_CACHE = 0,
    parameter CACHE_NUM_SETS = 8,
    parameter CACHE_WORDS_PER_LINE = 4
)(
    input wire clk,
    input wire rst,
    input wire imem_write_enable,
    input wire [31:0] imem_write_addr,
    input wire [31:0] imem_write_data,
    input wire [7:0] debug_imem_index,
    input wire [7:0] debug_dmem_index,
    input wire [4:0] debug_reg_index,
    input wire [31:0] external_read_data,
    output wire external_mem_read,
    output wire external_mem_write,
    output wire [31:0] external_addr,
    output wire [31:0] external_write_data,
    // ── Trap timer MMIO (connected to io_bus via top-level) ──
    input  wire        mtimecmp_mmio_write,
    input  wire [31:0] mtimecmp_mmio_wdata,
    output wire [31:0] mtime_mmio_val,
    output wire [31:0] mtimecmp_mmio_val,
    // ── External interrupt ──
    input  wire        irq_external,
    // ── Debug single-step ──
    input  wire        debug_stall,       // freeze pipeline (from top-level sw[8])
    output wire        trap_taken_out,    // trap_taken exposed to top-level for auto-break
    output wire stall_debug,
    output wire flush_debug,
    output wire predict_taken_debug,
    output wire inst_valid_debug,
    output wire [31:0] debug_cycle_count,
    output wire [31:0] debug_instret_count,
    output wire [31:0] debug_stall_count,
    output wire [31:0] debug_flush_count,
    output wire [31:0] debug_cache_access_count,
    output wire [31:0] debug_cache_hit_count,
    output wire [31:0] debug_cache_miss_count,
    output wire [31:0] debug_pc,
    output wire [31:0] debug_dmem0,
    output wire [31:0] debug_dmem1,
    output wire [31:0] debug_dmem_data,
    output wire [31:0] debug_imem_data,
    output wire [31:0] debug_reg_data
);
    wire [31:0] pc_value;
    wire [31:0] pc_plus4_if = pc_value + 32'd4;
    wire [31:0] inst_if;
    wire [31:0] next_pc;
    wire [31:0] correct_pc;

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
    wire id_is_system;
    wire id_mem_read;
    wire id_mem_to_reg;
    wire [1:0] id_alu_op;
    wire id_mem_write;
    wire id_alu_src;
    wire id_alu_a_zero;
    wire id_reg_write;
    wire [31:0] id_imm;
    wire id_pred_taken;
    wire id_predict_redirect;
    wire [31:0] id_pred_target;
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
    wire ex_alu_a_zero;
    wire [1:0] ex_alu_op;
    wire [31:0] ex_pc;
    wire [31:0] ex_reg_data1;
    wire [31:0] ex_reg_data2;
    wire [31:0] ex_imm;
    wire ex_pred_taken;
    wire [31:0] ex_pred_target;
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
    wire [31:0] ex_alu_a;
    wire [31:0] ex_alu_b;
    wire [31:0] ex_alu_result;
    wire ex_zero;
    wire ex_less_than;
    wire ex_less_than_unsigned;
    wire ex_pc_src;
    wire ex_mispredict;
    wire ex_is_div;
    wire ex_div_done;
    wire [31:0] ex_div_result;
    wire ex_is_system;
    wire ex_is_mret;
    wire ex_is_ecall;
    wire ex_is_csr;
    wire [11:0] ex_csr_addr;
    wire [31:0] ex_csr_wdata;      // rs1 value (or uimm) for CSR writes
    wire [31:0] csr_rdata;         // CSR read data → ex_result
    // trap control
    wire trap_taken;
    wire shadow_restore;
    wire [31:0] trap_target;
    wire [31:0] sh_ra, sh_sp, sh_t0, sh_t1, sh_t2;
    wire [31:0] mepc_val;
    // trap timer MMIO
    wire        mtimecmp_write;
    wire [31:0] mtimecmp_wdata;
    wire [31:0] mtime_val;
    wire [31:0] mtimecmp_val;
    reg  div_active;
    reg  div_result_valid;
    reg  [31:0] div_result_latched;
    wire div_start;
    wire div_stall;
    wire front_stall;
    wire id_ex_en;
    wire ex_mem_en;
    wire ex_mem_flush;
    wire [31:0] ex_result;
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
    wire [31:0] internal_mem_read_data;
    wire [31:0] mem_read_data;
    wire mem_access;
    wire mem_cacheable;
    wire cached_mem_access;
    wire cache_stall;
    wire external_bus_selected;

    wire cache_req_valid;
    wire cache_req_ready;
    wire cache_resp_valid;
    wire [31:0] cache_resp_rdata;
    wire cache_resp_hit;
    wire cache_busy;
    reg cache_req_sent;

    wire cache_mem_req_valid;
    wire cache_mem_req_ready;
    wire cache_mem_req_write;
    wire [31:0] cache_mem_req_addr;
    wire [31:0] cache_mem_req_wdata;
    wire cache_mem_resp_valid;
    wire [31:0] cache_mem_resp_rdata;

    wire backend_mem_read;
    wire backend_mem_write;
    wire [31:0] backend_addr;
    wire [31:0] backend_write_data;
    wire [31:0] backend_read_data;
    wire direct_mem_read;
    wire direct_mem_write;
    wire storage_mem_read;
    wire storage_mem_write;
    wire [31:0] storage_addr;
    wire [31:0] storage_write_data;
    wire [31:0] cache_access_count;
    wire [31:0] cache_hit_count;
    wire [31:0] cache_miss_count;

    wire wb_reg_write;
    wire wb_mem_to_reg;
    wire wb_jal;
    wire [31:0] wb_pc_plus4;
    wire [31:0] wb_mem_data;
    wire [31:0] wb_alu_result;
    wire [4:0] wb_rd;
    wire [31:0] wb_data;
    wire wb_commit_write;

    wire pc_write;
    wire if_id_write;
    wire if_id_flush;
    wire hazard_if_id_flush;
    wire id_ex_flush;
    wire load_use_stall;
    wire inst_valid_wb;
    reg if_id_valid;
    reg id_ex_valid;
    reg ex_mem_valid;
    reg mem_wb_valid;

    assign id_pred_taken = id_jal | (id_branch & id_imm[31]);
    assign id_pred_target = if_id_pc + id_imm;
    assign id_predict_redirect = pc_write & if_id_valid & id_pred_taken;

    assign ex_mispredict = id_ex_valid & (ex_branch | ex_jal) &
        ((ex_pc_src != ex_pred_taken) |
        (ex_pc_src & ex_pred_taken & (ex_branch_target != ex_pred_target)));
    assign correct_pc = ex_pc_src ? ex_branch_target : ex_pc_plus4;
    wire ex_mret_taken;              // MRET in EX stage → redirect PC + flush IF/ID
    // PC selection priority: trap > mret(EX) > mret(MEM fallback) > mispredict > predict-redirect > sequential
    assign next_pc = trap_taken         ? trap_target :
                     ex_mret_taken      ? mepc_val :
                     shadow_restore     ? mepc_val :
                     ex_mispredict      ? correct_pc :
                     id_predict_redirect? id_pred_target :
                                          pc_plus4_if;

    assign ex_mret_taken = ex_is_mret && id_ex_valid && !id_ex_flush;
    // MRET must NOT flush ID/EX — the instruction must flow EX→MEM→WB
    // so that shadow_restore fires and MIE/shadow regs are restored.
    // Only IF/ID is flushed (via if_id_flush below) to kill the instruction
    // that follows MRET.
    wire id_ex_flush_reg = id_ex_flush;

    // --- multi-cycle division control ---
    assign ex_is_div   = id_ex_valid &&
        ((ex_alu_ctrl == `ALU_DIV)  ||
         (ex_alu_ctrl == `ALU_DIVU) ||
         (ex_alu_ctrl == `ALU_REM)  ||
         (ex_alu_ctrl == `ALU_REMU));
    assign div_start   = ex_is_div && !div_active && !div_result_valid && !ex_div_done;
    assign div_stall   = ex_is_div && !div_result_valid && !ex_div_done;
    assign front_stall = div_stall | cache_stall;
    assign id_ex_en    = ~front_stall & ~debug_stall;
    // BUG #5 fix: Freeze EX/MEM during div_stall instead of flushing.
    // The old ex_mem_flush=div_stall cleared EX/MEM on the same clock edge
    // that io_bus was sampling the write-enable for the previous SW in MEM,
    // causing a race that lost the write to dmem.
    assign ex_mem_en   = ~cache_stall & ~div_stall & ~debug_stall;
    assign ex_mem_flush = 1'b0;
    // EX result: division > CSR read > ALU
    assign ex_result   = ex_is_div  ? (div_result_valid ? div_result_latched : ex_div_result) :
                         ex_is_csr  ? csr_rdata :
                         ex_alu_result;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            div_active <= 1'b0;
            div_result_valid <= 1'b0;
            div_result_latched <= 32'b0;
        end else begin
            if (div_start) begin
                div_active <= 1'b1;
            end
            if (ex_div_done) begin
                div_active <= 1'b0;
                div_result_valid <= 1'b1;
                div_result_latched <= ex_div_result;
            end
            if (ex_is_div && !front_stall && (div_result_valid || ex_div_done)) begin
                div_result_valid <= 1'b0;
            end
        end
    end

    pc u_pc(.clk(clk), .rst(rst), .en(pc_write), .next_pc(next_pc), .pc(pc_value));
    imem #(.INIT_FILE(INIT_FILE), .USE_INIT_FILE(USE_INIT_FILE), .PROGRAM_ID(PROGRAM_ID)) u_imem(
        .addr(pc_value),
        .clk(clk),
        .write_enable(ENABLE_IMEM_WRITE ? imem_write_enable : 1'b0),
        .write_addr(imem_write_addr),
        .write_data(imem_write_data),
        .debug_index(debug_imem_index),
        .inst(inst_if),
        .debug_data(debug_imem_data)
    );

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
    control u_control(.opcode(id_opcode), .branch(id_branch), .jal(id_jal), .mem_read(id_mem_read), .mem_to_reg(id_mem_to_reg), .alu_op(id_alu_op), .mem_write(id_mem_write), .alu_src(id_alu_src), .alu_a_zero(id_alu_a_zero), .reg_write(id_reg_write), .is_system(id_is_system));
    imm_gen u_imm_gen(.inst(if_id_inst), .imm(id_imm));
    wire [31:0] reg_x1, reg_x2, reg_x5, reg_x6, reg_x7;  // for trap shadow capture
    assign wb_commit_write = wb_reg_write && mem_wb_valid;
    regfile u_regfile(.clk(clk), .rst(rst), .reg_write(wb_commit_write), .rs1(id_rs1), .rs2(id_rs2), .rd(wb_rd), .write_data(wb_data), .debug_index(debug_reg_index), .read_data1(id_reg_data1), .read_data2(id_reg_data2), .debug_data(debug_reg_data), .shadow_restore(shadow_restore), .sh_ra(sh_ra), .sh_sp(sh_sp), .sh_t0(sh_t0), .sh_t1(sh_t1), .sh_t2(sh_t2), .x1_val(reg_x1), .x2_val(reg_x2), .x5_val(reg_x5), .x6_val(reg_x6), .x7_val(reg_x7));
    assign id_reg_data1_bypass = (wb_commit_write && wb_rd != 5'b0 && wb_rd == id_rs1) ? wb_data : id_reg_data1;
    assign id_reg_data2_bypass = (wb_commit_write && wb_rd != 5'b0 && wb_rd == id_rs2) ? wb_data : id_reg_data2;

    hazard_unit u_hazard(
        .id_ex_mem_read(ex_mem_read), .id_ex_rd(ex_rd), .if_id_rs1(id_rs1), .if_id_rs2(id_rs2),
        .pc_src(ex_mispredict), .ex_stall(front_stall), .trap_taken(trap_taken),
        .debug_stall(debug_stall),   // debug single-step
        .pc_write(pc_write), .if_id_write(if_id_write), .if_id_flush(hazard_if_id_flush), .id_ex_flush(id_ex_flush)
    );
    assign if_id_flush = hazard_if_id_flush | id_predict_redirect | ex_mret_taken;
    assign load_use_stall = ~pc_write && !front_stall;

    id_ex_reg u_id_ex(
        .clk(clk), .rst(rst), .en(id_ex_en), .flush(id_ex_flush_reg),
        .reg_write_in(id_reg_write), .mem_to_reg_in(id_mem_to_reg), .mem_read_in(id_mem_read), .mem_write_in(id_mem_write),
        .branch_in(id_branch), .jal_in(id_jal), .is_system_in(id_is_system), .alu_src_in(id_alu_src), .alu_a_zero_in(id_alu_a_zero), .alu_op_in(id_alu_op),
        .pc_in(if_id_pc), .reg_data1_in(id_reg_data1_bypass), .reg_data2_in(id_reg_data2_bypass), .imm_in(id_imm),
        .pred_taken_in(id_pred_taken), .pred_target_in(id_pred_target),
        .rs1_in(id_rs1), .rs2_in(id_rs2), .rd_in(id_rd), .funct3_in(id_funct3), .funct7_in(id_funct7),
        .reg_write_out(ex_reg_write), .mem_to_reg_out(ex_mem_to_reg), .mem_read_out(ex_mem_read), .mem_write_out(ex_mem_write),
        .branch_out(ex_branch), .jal_out(ex_jal), .is_system_out(ex_is_system), .alu_src_out(ex_alu_src), .alu_a_zero_out(ex_alu_a_zero), .alu_op_out(ex_alu_op),
        .pc_out(ex_pc), .reg_data1_out(ex_reg_data1), .reg_data2_out(ex_reg_data2), .imm_out(ex_imm),
        .pred_taken_out(ex_pred_taken), .pred_target_out(ex_pred_target),
        .rs1_out(ex_rs1), .rs2_out(ex_rs2), .rd_out(ex_rd), .funct3_out(ex_funct3), .funct7_out(ex_funct7)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            id_ex_valid <= 1'b0;
        end else if (id_ex_flush_reg) begin
            id_ex_valid <= 1'b0;
        end else if (id_ex_en) begin
            id_ex_valid <= if_id_valid;
        end
    end

    forwarding_unit u_forwarding(
        .ex_mem_reg_write(mem_reg_write && ex_mem_valid), .ex_mem_rd(mem_rd), .mem_wb_reg_write(wb_commit_write), .mem_wb_rd(wb_rd),
        .id_ex_rs1(ex_rs1), .id_ex_rs2(ex_rs2), .forward_a(forward_a), .forward_b(forward_b)
    );

    assign forward_a_data = (forward_a == 2'b10) ? mem_alu_result :
                            (forward_a == 2'b01) ? wb_data : ex_reg_data1;
    assign forward_b_data = (forward_b == 2'b10) ? mem_alu_result :
                            (forward_b == 2'b01) ? wb_data : ex_reg_data2;

    alu_control u_alu_control(.alu_op(ex_alu_op), .funct3(ex_funct3), .funct7(ex_funct7), .alu_ctrl(ex_alu_ctrl));
    // ── SYSTEM instruction decode (EX stage) ──
    assign ex_is_mret  = ex_is_system && (ex_funct3 == 3'b000) && (ex_funct7 == 7'b0011000) && (ex_rs2 == 5'b00010);
    assign ex_is_ecall = ex_is_system && (ex_funct3 == 3'b000) && (ex_funct7 == 7'b0000000) && (ex_rs2 == 5'b00000);
    assign ex_is_csr   = ex_is_system && !ex_is_mret && !ex_is_ecall;
    assign ex_csr_addr = {ex_funct7, ex_rs2};           // CSR address = funct7 + rs2
    wire ex_csr_is_imm = ex_is_csr && ex_funct3[2];     // funct3>=4 → immediate form
    assign ex_csr_wdata = ex_csr_is_imm ? {27'b0, ex_rs1} : ex_alu_a;  // imm: uimm, reg: rs1 value
    // CSR write enable: skip write for CSRRS/CSRRC with rs1=x0 (read-only CSR access)
    wire ex_csr_no_write = ((ex_funct3 == 3'b010 || ex_funct3 == 3'b011) && ex_rs1 == 5'd0) ||
                           ((ex_funct3 == 3'b110 || ex_funct3 == 3'b111) && ex_rs1 == 5'd0);
    wire ex_csr_write = ex_is_csr && !ex_csr_no_write;
    assign ex_alu_a = ex_alu_a_zero ? 32'b0 : forward_a_data;
    assign ex_alu_b = ex_alu_src ? ex_imm : forward_b_data;
    alu u_alu(.a(ex_alu_a), .b(ex_alu_b), .alu_ctrl(ex_alu_ctrl),
              .y(ex_alu_result), .zero(ex_zero),
              .less_than(ex_less_than), .less_than_unsigned(ex_less_than_unsigned));
    branch_unit u_branch_unit(.branch(ex_branch), .jal(ex_jal), .zero(ex_zero),
                              .less_than(ex_less_than), .less_than_unsigned(ex_less_than_unsigned),
                              .funct3(ex_funct3), .pc_src(ex_pc_src));

    div_unit u_div_unit(
        .clk(clk), .rst(rst),
        .start(div_start),
        .dividend(ex_alu_a), .divisor(ex_alu_b),
        .funct3(ex_funct3),
        .result(ex_div_result), .done(ex_div_done)
    );

    trap_csr_unit u_trap(
        .clk(clk), .rst(rst),
        .irq_external(irq_external),       // connected from top-level via editable_pipeline_system_top
        .reg_x1(reg_x1), .reg_x2(reg_x2), .reg_x5(reg_x5), .reg_x6(reg_x6), .reg_x7(reg_x7),
        .wb_commit_write(wb_commit_write), .wb_rd(wb_rd), .wb_data(wb_data),
        .ex_is_csr(ex_is_csr), .ex_is_mret(ex_is_mret), .ex_is_ecall(ex_is_ecall),
        .ex_csr_addr(ex_csr_addr), .ex_csr_wdata(ex_csr_wdata), .ex_csr_write(ex_csr_write),
        .ex_csr_funct3(ex_funct3),
        .csr_rdata(csr_rdata),
        .id_pc(if_id_pc),
        .ex_pc(ex_pc),
        .id_ex_valid(id_ex_valid),
        .id_ex_flush(id_ex_flush), .ex_mem_valid(ex_mem_valid),
        .ex_mem_flush(ex_mem_flush), .mem_wb_valid(mem_wb_valid),
        .trap_taken(trap_taken), .trap_target(trap_target),
        .shadow_restore(shadow_restore),
        .sh_ra(sh_ra), .sh_sp(sh_sp), .sh_t0(sh_t0), .sh_t1(sh_t1), .sh_t2(sh_t2),
        .mepc_val(mepc_val),
        .io_mtimecmp_write(mtimecmp_write), .io_mtimecmp_wdata(mtimecmp_wdata),
        .io_mtime_val(mtime_val), .io_mtimecmp_val(mtimecmp_val)
    );

    ex_mem_reg u_ex_mem(
        .clk(clk), .rst(rst), .en(ex_mem_en), .flush(ex_mem_flush),
        .reg_write_in(ex_reg_write), .mem_to_reg_in(ex_mem_to_reg), .mem_read_in(ex_mem_read), .mem_write_in(ex_mem_write),
        .jal_in(ex_jal), .pc_plus4_in(ex_pc_plus4), .alu_result_in(ex_result), .write_data_in(forward_b_data), .rd_in(ex_rd),
        .reg_write_out(mem_reg_write), .mem_to_reg_out(mem_mem_to_reg), .mem_read_out(mem_mem_read), .mem_write_out(mem_mem_write),
        .jal_out(mem_jal), .pc_plus4_out(mem_pc_plus4), .alu_result_out(mem_alu_result), .write_data_out(mem_write_data), .rd_out(mem_rd)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ex_mem_valid <= 1'b0;
        end else if (cache_stall) begin
            ex_mem_valid <= ex_mem_valid;
        end else if (div_stall) begin
            ex_mem_valid <= 1'b0;
        end else begin
            ex_mem_valid <= id_ex_valid;
        end
    end

    assign mem_access = ex_mem_valid && (mem_mem_read || mem_mem_write);
    assign mem_cacheable = (mem_alu_result[31:10] == 22'b0);
    assign cached_mem_access = ENABLE_DATA_CACHE && mem_access && mem_cacheable;
    assign cache_req_valid = cached_mem_access && !cache_req_sent;
    assign cache_stall = cached_mem_access && !cache_resp_valid;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cache_req_sent <= 1'b0;
        end else if (!cached_mem_access || cache_resp_valid) begin
            cache_req_sent <= 1'b0;
        end else if (cache_req_valid && cache_req_ready) begin
            cache_req_sent <= 1'b1;
        end
    end

    data_cache #(
        .ADDR_WIDTH(32),
        .DATA_WIDTH(32),
        .NUM_SETS(CACHE_NUM_SETS),
        .WORDS_PER_LINE(CACHE_WORDS_PER_LINE)
    ) u_data_cache (
        .clk(clk),
        .rst(rst),
        .req_valid(cache_req_valid),
        .req_ready(cache_req_ready),
        .req_write(mem_mem_write),
        .req_addr(mem_alu_result),
        .req_wdata(mem_write_data),
        .resp_valid(cache_resp_valid),
        .resp_rdata(cache_resp_rdata),
        .resp_hit(cache_resp_hit),
        .busy(cache_busy),
        .mem_req_valid(cache_mem_req_valid),
        .mem_req_ready(cache_mem_req_ready),
        .mem_req_write(cache_mem_req_write),
        .mem_req_addr(cache_mem_req_addr),
        .mem_req_wdata(cache_mem_req_wdata),
        .mem_resp_valid(cache_mem_resp_valid),
        .mem_resp_rdata(cache_mem_resp_rdata),
        .access_count(cache_access_count),
        .hit_count(cache_hit_count),
        .miss_count(cache_miss_count)
    );

    cache_memory_adapter u_cache_memory_adapter (
        .clk(clk),
        .rst(rst),
        .req_valid(cache_mem_req_valid),
        .req_ready(cache_mem_req_ready),
        .req_write(cache_mem_req_write),
        .req_addr(cache_mem_req_addr),
        .req_wdata(cache_mem_req_wdata),
        .resp_valid(cache_mem_resp_valid),
        .resp_rdata(cache_mem_resp_rdata),
        .backend_mem_read(backend_mem_read),
        .backend_mem_write(backend_mem_write),
        .backend_addr(backend_addr),
        .backend_write_data(backend_write_data),
        .backend_read_data(backend_read_data)
    );

    assign direct_mem_read = mem_access && mem_mem_read &&
        (!ENABLE_DATA_CACHE || !mem_cacheable);
    assign direct_mem_write = mem_access && mem_mem_write &&
        (!ENABLE_DATA_CACHE || !mem_cacheable);

    assign storage_mem_read = ENABLE_DATA_CACHE ?
        (backend_mem_read || direct_mem_read) : direct_mem_read;
    assign storage_mem_write = ENABLE_DATA_CACHE ?
        (backend_mem_write || direct_mem_write) : direct_mem_write;
    assign storage_addr = (ENABLE_DATA_CACHE &&
        (backend_mem_read || backend_mem_write)) ? backend_addr : mem_alu_result;
    assign storage_write_data = (ENABLE_DATA_CACHE && backend_mem_write) ?
        backend_write_data : mem_write_data;

    dmem u_dmem(
        .clk(clk),
        .mem_read(storage_mem_read && !external_bus_selected),
        .mem_write(storage_mem_write && !external_bus_selected),
        .addr(storage_addr),
        .write_data(storage_write_data),
        .debug_index(debug_dmem_index),
        .read_data(internal_mem_read_data),
        .debug_data(debug_dmem_data)
    );

    assign external_bus_selected = USE_EXTERNAL_DATA_BUS &&
        (storage_addr[31:16] == 16'h1000) &&
        (storage_mem_read || storage_mem_write);
    assign backend_read_data = internal_mem_read_data;
    assign mem_read_data = cached_mem_access ? cache_resp_rdata :
        (external_bus_selected ? external_read_data : internal_mem_read_data);

    mem_wb_reg u_mem_wb(
        .clk(clk), .rst(rst), .en(1'b1), .flush(cache_stall),
        .reg_write_in(mem_reg_write), .mem_to_reg_in(mem_mem_to_reg), .jal_in(mem_jal),
        .pc_plus4_in(mem_pc_plus4), .mem_data_in(mem_read_data), .alu_result_in(mem_alu_result), .rd_in(mem_rd),
        .reg_write_out(wb_reg_write), .mem_to_reg_out(wb_mem_to_reg), .jal_out(wb_jal),
        .pc_plus4_out(wb_pc_plus4), .mem_data_out(wb_mem_data), .alu_result_out(wb_alu_result), .rd_out(wb_rd)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_wb_valid <= 1'b0;
        end else if (cache_stall) begin
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
        .stall(load_use_stall | div_stall | cache_stall),
        .flush(ex_mispredict | id_predict_redirect),
        .cycle_count(debug_cycle_count),
        .instret_count(debug_instret_count),
        .stall_count(debug_stall_count),
        .flush_count(debug_flush_count)
    );

    assign stall_debug = load_use_stall | div_stall | cache_stall;
    assign flush_debug = ex_mispredict | id_predict_redirect;
    assign predict_taken_debug = id_predict_redirect;
    assign inst_valid_debug = inst_valid_wb;
    assign external_mem_read = external_bus_selected ? storage_mem_read : 1'b0;
    assign external_mem_write = external_bus_selected ? storage_mem_write : 1'b0;
    assign external_addr = storage_addr;
    assign external_write_data = storage_write_data;
    // ── Trap timer MMIO pass-through ──
    assign mtime_mmio_val    = mtime_val;
    assign mtimecmp_mmio_val = mtimecmp_val;
    assign mtimecmp_write    = mtimecmp_mmio_write;
    assign mtimecmp_wdata    = mtimecmp_mmio_wdata;
    assign debug_cache_access_count = ENABLE_DATA_CACHE ? cache_access_count : 32'b0;
    assign debug_cache_hit_count = ENABLE_DATA_CACHE ? cache_hit_count : 32'b0;
    assign debug_cache_miss_count = ENABLE_DATA_CACHE ? cache_miss_count : 32'b0;
    assign debug_pc = pc_value;
    assign debug_dmem0 = u_dmem.mem[0];
    assign debug_dmem1 = u_dmem.mem[1];
    assign trap_taken_out = trap_taken;
endmodule
