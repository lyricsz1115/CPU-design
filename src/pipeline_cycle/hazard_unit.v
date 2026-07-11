module hazard_unit(
    input wire id_ex_mem_read,
    input wire [4:0] id_ex_rd,
    input wire [4:0] if_id_rs1,
    input wire [4:0] if_id_rs2,
    input wire pc_src,
    input wire ex_stall,          // multi-cycle EX (division) in progress
    output wire pc_write,
    output wire if_id_write,
    output wire if_id_flush,
    output wire id_ex_flush
);
    wire load_use = id_ex_mem_read &&
        (id_ex_rd != 5'b0) &&
        ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2));

    // During multi-cycle EX, freeze IF/ID and PC; don't flush ID/EX
    assign pc_write    = ~load_use && ~ex_stall;
    assign if_id_write = ~load_use && ~ex_stall;
    assign if_id_flush = pc_src;
    assign id_ex_flush = (load_use | pc_src) & ~ex_stall;
endmodule
