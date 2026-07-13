// ============================================================================
// trap_csr_unit.v — RISC-V Machine-mode trap controller with shadow registers
// ============================================================================
// Features:
//   - CSR register bank: mstatus(MIE/MPIE), mtvec, mepc, mcause, mie, mip
//   - 5 shadow registers: x1(ra), x2(sp), x5(t0), x6(t1), x7(t2)
//   - 32-bit mtime counter + mtimecmp comparator → timer interrupt (MTIP)
//   - Interrupt arbitration: trap_taken = mstatus_MIE & |(mie & mip)
//   - MRET restore and redirect at one EX-stage commit boundary
//   - Shadow capture receives the newest EX/MEM/WB-visible register values
// ============================================================================

module trap_csr_unit (
    input  wire        clk,
    input  wire        rst,

    // ── Interrupt sources ──
    input  wire        irq_external,       // MEIP: external button
    output wire        irq_external_ack,   // pulse when an external IRQ is accepted

    // ── Register file snapshot interface ──
    input  wire [31:0] reg_x1,             // x1 (ra) current value
    input  wire [31:0] reg_x2,             // x2 (sp) current value
    input  wire [31:0] reg_x5,             // x5 (t0) current value
    input  wire [31:0] reg_x6,             // x6 (t1) current value
    input  wire [31:0] reg_x7,             // x7 (t2) current value

    // ── WB stage write-back info (for conflict resolution) ──
    input  wire        wb_commit_write,    // WB is writing regfile
    input  wire [4:0]  wb_rd,              // WB destination register
    input  wire [31:0] wb_data,            // WB write data

    // ── CSR operation interface (from EX stage) ──
    input  wire        ex_is_csr,          // EX instruction is CSR read/write
    input  wire        ex_is_mret,         // EX instruction is MRET
    input  wire        ex_is_ecall,        // EX instruction is ECALL
    input  wire        interrupt_accept,   // asynchronous IRQ can enter now
    input  wire        trap_stage_ready,   // EX trap instruction can commit now
    input  wire [11:0] ex_csr_addr,        // 12-bit CSR address
    input  wire [31:0] ex_csr_wdata,       // write data for CSR (rs1 or uimm)
    input  wire        ex_csr_write,       // 1 = this CSR instruction writes CSR
    output reg  [31:0] csr_rdata,          // CSR read data → ex_result → regfile

    input  wire [2:0]  ex_csr_funct3,      // funct3 for CSR instruction (RMW type)
    // ── Pipeline control interface ──
    input  wire [31:0] id_pc,              // ID stage PC (for interrupt mepc)
    input  wire [31:0] ex_pc,              // EX stage PC (for ECALL mepc)
    input  wire        id_ex_valid,
    input  wire        id_ex_flush,
    output wire        trap_taken,         // 1-cycle pulse: take trap now
    output wire [31:0] trap_target,        // mtvec value (trap handler address)
    output wire        shadow_restore,     // 1-cycle pulse: restore shadows → regfile

    // ── Shadow register outputs (to regfile for batch restore) ──
    output wire [31:0] sh_ra,
    output wire [31:0] sh_sp,
    output wire [31:0] sh_t0,
    output wire [31:0] sh_t1,
    output wire [31:0] sh_t2,

    // ── mepc output (for PC redirection on MRET) ──
    output wire [31:0] mepc_val,

    // ── mtime/mtimecmp MMIO interface (to io_bus) ──
    input  wire        io_mtimecmp_write,  // io_bus write to mtimecmp
    input  wire [31:0] io_mtimecmp_wdata,
    output wire [31:0] io_mtime_val,       // current mtime (read-only)
    output wire [31:0] io_mtimecmp_val     // current mtimecmp (read-only)
);

    // ========================================================================
    // CSR addresses
    // ========================================================================
    localparam CSR_MSTATUS  = 12'h300;
    localparam CSR_MTVEC    = 12'h305;
    localparam CSR_MEPC     = 12'h341;
    localparam CSR_MCAUSE   = 12'h342;
    localparam CSR_MIE      = 12'h304;
    localparam CSR_MIP      = 12'h344;

    // ========================================================================
    // mcause encodings
    // ========================================================================
    localparam [31:0] MCAUSE_MTIP   = 32'h80000007;  // Machine timer interrupt
    localparam [31:0] MCAUSE_MEIP   = 32'h8000000B;  // Machine external interrupt
    localparam [31:0] MCAUSE_MSIP   = 32'h80000003;  // Machine software interrupt
    localparam [31:0] MCAUSE_ECALL  = 32'h0000000B;  // Environment call from M-mode

    // ========================================================================
    // CSR registers
    // ========================================================================
    reg         mstatus_MIE;        // bit 3: global interrupt enable
    reg         mstatus_MPIE;       // bit 7: previous MIE (saved on trap)
    reg [31:0]  mtvec;              // trap vector base address
    reg [31:0]  mepc;               // exception program counter
    reg [31:0]  mcause;             // trap cause
    reg [11:0]  mie;                // interrupt enable (bits 7=MTIE, 11=MEIE, 3=MSIE)
    reg [31:0]  mtimecmp;           // machine timer compare value
    reg [31:0]  mtime;              // machine timer counter

    // ── mip: combinatorial reflection of pending interrupts ──
    wire [11:0] mip;
    assign mip[7]  = (mtime >= mtimecmp);              // MTIP (bit 7)
    assign mip[11] = irq_external;                     // MEIP (bit 11)
    assign mip[3]  = 1'b0;                             // MSIP (bit 3, not used)
    assign mip[2:0] = 3'b0;
    assign mip[6:4] = 3'b0;
    assign mip[10:8] = 3'b0;

    assign io_mtime_val    = mtime;
    assign io_mtimecmp_val = mtimecmp;

    // ========================================================================
    // mtime counter — free-running, increments every cycle
    // ========================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mtime <= 32'b0;
        end else begin
            mtime <= mtime + 32'd1;
        end
    end

    // ========================================================================
    // mtimecmp — software write from io_bus
    // ========================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mtimecmp <= 32'hFFFFFFFF;   // max value → won't trigger until set
        end else if (io_mtimecmp_write) begin
            mtimecmp <= io_mtimecmp_wdata;
        end
    end

    // ========================================================================
    // Interrupt detection (combinatorial)
    // ========================================================================
    wire interrupt_pending = |(mie & mip);  // any enabled interrupt pending?
    wire trap_condition    = interrupt_pending & mstatus_MIE;

    // ========================================================================
    // Trap cause encoding (combinatorial, priority: external > timer > software)
    // ========================================================================
    wire [31:0] cause_encoded;
    assign cause_encoded = (mip[11] & mie[11]) ? MCAUSE_MEIP :   // external
                           (mip[7]  & mie[7])  ? MCAUSE_MTIP :   // timer
                           (mip[3]  & mie[3])  ? MCAUSE_MSIP :   // software
                                                 32'b0;

    // ========================================================================
    // ECALL trap detection (from EX stage)
    // ========================================================================
    wire interrupt_taken = trap_condition && interrupt_accept;
    wire ecall_taken = ex_is_ecall && id_ex_valid && trap_stage_ready;

    // ========================================================================
    // trap_taken: asserted when interrupt or ECALL triggers
    // ========================================================================
    assign trap_taken   = interrupt_taken | ecall_taken;
    assign trap_target  = mtvec;
    assign mepc_val     = mepc;
    assign irq_external_ack = interrupt_taken &&
                              (cause_encoded == MCAUSE_MEIP);

    // ========================================================================
    // Shadow registers — capture x1/x2/x5/x6/x7 at trap_taken.
    // The CPU snapshot inputs already include EX/MEM/WB forwarding. Keep the
    // WB override here as a defensive guarantee for direct unit-level users.
    // ========================================================================
    reg [31:0] sh_ra_r, sh_sp_r, sh_t0_r, sh_t1_r, sh_t2_r;

    assign sh_ra = sh_ra_r;
    assign sh_sp = sh_sp_r;
    assign sh_t0 = sh_t0_r;
    assign sh_t1 = sh_t1_r;
    assign sh_t2 = sh_t2_r;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sh_ra_r <= 32'b0;
            sh_sp_r <= 32'b0;
            sh_t0_r <= 32'b0;
            sh_t1_r <= 32'b0;
            sh_t2_r <= 32'b0;
        end else if (trap_taken) begin
            // ★ CRITICAL: Check if WB is writing the same register this cycle.
            // If so, capture wb_data (the correct new value) instead of the
            // old regfile value that hasn't been updated yet (non-blocking).
            sh_ra_r <= (wb_commit_write && wb_rd == 5'd1)  ? wb_data : reg_x1;
            sh_sp_r <= (wb_commit_write && wb_rd == 5'd2)  ? wb_data : reg_x2;
            sh_t0_r <= (wb_commit_write && wb_rd == 5'd5)  ? wb_data : reg_x5;
            sh_t1_r <= (wb_commit_write && wb_rd == 5'd6)  ? wb_data : reg_x6;
            sh_t2_r <= (wb_commit_write && wb_rd == 5'd7)  ? wb_data : reg_x7;
        end
    end

    // ========================================================================
    // MRET restore and PC redirect share one EX-stage commit event.
    // ========================================================================
    assign shadow_restore = ex_is_mret && id_ex_valid &&
                            trap_stage_ready && !id_ex_flush;

    // ========================================================================
    // CSR read-modify-write data path (combinatorial, used by CSR writes below)
    // ========================================================================
    wire [31:0] csr_old_val;
    assign csr_old_val =
        (ex_csr_addr == CSR_MSTATUS) ? {24'b0, mstatus_MPIE, 3'b0, mstatus_MIE, 3'b0} :
        (ex_csr_addr == CSR_MTVEC)   ? mtvec   :
        (ex_csr_addr == CSR_MEPC)    ? mepc    :
        (ex_csr_addr == CSR_MCAUSE)  ? mcause  :
        (ex_csr_addr == CSR_MIE)     ? {20'b0, mie} :
        (ex_csr_addr == CSR_MIP)     ? {20'b0, mip} :
                                        32'b0;
    // funct3: 001=CSRRW, 010=CSRRS, 011=CSRRC, 101=CSRRWI, 110=CSRRSI, 111=CSRRCI
    wire [31:0] csr_wdata_rmw;
    assign csr_wdata_rmw =
        (ex_csr_funct3 == 3'b010 || ex_csr_funct3 == 3'b110) ? (csr_old_val |  ex_csr_wdata) :
        (ex_csr_funct3 == 3'b011 || ex_csr_funct3 == 3'b111) ? (csr_old_val & ~ex_csr_wdata) :
                                                                 ex_csr_wdata;

    // ========================================================================
    // CSR register updates — trap entry, MRET, and software CSR writes
    // ========================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mstatus_MIE  <= 1'b0;
            mstatus_MPIE <= 1'b0;
            mtvec        <= 32'b0;
            mepc         <= 32'b0;
            mcause       <= 32'b0;
            mie          <= 12'b0;
        end else begin
            // ── Trap entry (interrupt or ECALL): save state atomically ──
            if (trap_taken) begin
                mepc         <= ecall_taken ? ex_pc : id_pc;
                mcause       <= ecall_taken ? MCAUSE_ECALL : cause_encoded;
                mstatus_MPIE <= mstatus_MIE;
                mstatus_MIE  <= 1'b0;
            end
            // ── MRET exit: restore MIE from MPIE ──
            else if (shadow_restore) begin
                mstatus_MIE  <= mstatus_MPIE;
                mstatus_MPIE <= 1'b1;
            end
            // ── Software CSR write (CSRRW / CSRRS / CSRRC / etc. in EX) ──
            else if (ex_is_csr && ex_csr_write && id_ex_valid && !id_ex_flush) begin
                case (ex_csr_addr)
                    CSR_MSTATUS: begin
                        mstatus_MIE  <= csr_wdata_rmw[3];
                        mstatus_MPIE <= csr_wdata_rmw[7];
                    end
                    CSR_MTVEC:   mtvec  <= csr_wdata_rmw;
                    CSR_MEPC:    mepc   <= csr_wdata_rmw;
                    CSR_MCAUSE:  mcause <= csr_wdata_rmw;
                    CSR_MIE:     mie    <= csr_wdata_rmw[11:0] & 12'h888;
                    CSR_MIP:     ; // mip is read-only (hardware-driven)
                    default:     ;
                endcase
            end
        end
    end

    // ========================================================================
    // CSR read — combinatorial output based on CSR address
    // ========================================================================
    always @(*) begin
        case (ex_csr_addr)
            CSR_MSTATUS: csr_rdata = {24'b0, mstatus_MPIE, 3'b0, mstatus_MIE, 3'b0};
            CSR_MTVEC:   csr_rdata = mtvec;
            CSR_MEPC:    csr_rdata = mepc;
            CSR_MCAUSE:  csr_rdata = mcause;
            CSR_MIE:     csr_rdata = {20'b0, mie};
            CSR_MIP:     csr_rdata = {20'b0, mip};
            default:     csr_rdata = 32'b0;
        endcase
    end

endmodule
