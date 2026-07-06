module hazard_unit(
    input wire id_ex_mem_read,
    input wire [4:0] id_ex_rd,
    input wire [4:0] if_id_rs1,
    input wire [4:0] if_id_rs2,
    input wire pc_src,
    output wire pc_write,
    output wire if_id_write,
    output wire if_id_flush,
    output wire id_ex_flush
);
    wire load_use = id_ex_mem_read &&
        (id_ex_rd != 5'b0) &&
        ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2));

    assign pc_write = ~load_use;
    assign if_id_write = ~load_use;
    assign if_id_flush = pc_src;
    assign id_ex_flush = load_use | pc_src;
endmodule
