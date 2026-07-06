module branch_unit(
    input wire branch,
    input wire jal,
    input wire zero,
    output wire pc_src
);
    assign pc_src = jal | (branch & zero);
endmodule
