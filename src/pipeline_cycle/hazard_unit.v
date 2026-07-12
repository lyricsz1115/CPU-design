module hazard_unit(
    input wire id_ex_mem_read,
    input wire [4:0] id_ex_rd,
    input wire [4:0] if_id_rs1,
    input wire [4:0] if_id_rs2,
    input wire pc_src,
    input wire ex_stall,          // multi-cycle EX (division) in progress
    input wire trap_taken,        // interrupt/exception trap
    input wire debug_stall,       // debug single-step freeze (from top-level)
    output wire pc_write,
    output wire if_id_write,
    output wire if_id_flush,
    output wire id_ex_flush
);
    wire load_use = id_ex_mem_read &&
        (id_ex_rd != 5'b0) &&
        ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2));

    // During multi-cycle EX, freeze IF/ID and PC; don't flush ID/EX.
    // trap_taken overrides ex_stall: interrupt must redirect PC and flush
    // even when division is in progress.
    // debug_stall: top-level single-step freeze (sw[8] debug mode).
    assign pc_write    = trap_taken | (~load_use && ~ex_stall && ~debug_stall);
    assign if_id_write = trap_taken | (~load_use && ~ex_stall && ~debug_stall);
    assign if_id_flush = pc_src | trap_taken;
    assign id_ex_flush = trap_taken | ((load_use | pc_src) & ~ex_stall);
endmodule
