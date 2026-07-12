module regfile(
    input wire clk,
    input wire rst,
    input wire reg_write,
    input wire [4:0] rs1,
    input wire [4:0] rs2,
    input wire [4:0] rd,
    input wire [31:0] write_data,
    input wire [4:0] debug_index,
    output wire [31:0] read_data1,
    output wire [31:0] read_data2,
    output wire [31:0] debug_data,
    // ── Shadow register restore (trap unit) ──
    input  wire        shadow_restore,
    input  wire [31:0] sh_ra,
    input  wire [31:0] sh_sp,
    input  wire [31:0] sh_t0,
    input  wire [31:0] sh_t1,
    input  wire [31:0] sh_t2,
    // ── Key register values exposed for shadow capture ──
    output wire [31:0] x1_val,
    output wire [31:0] x2_val,
    output wire [31:0] x5_val,
    output wire [31:0] x6_val,
    output wire [31:0] x7_val
);
    reg [31:0] regs [0:31];
    integer i;
//write,in RISC_V, x0 is always zero, don't write to it.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1) begin
                regs[i] <= 32'b0;
            end
        end else begin
            // ── Priority 1: shadow restore (batch write 5 regs in 1 cycle) ──
            if (shadow_restore) begin
                regs[1] <= sh_ra;
                regs[2] <= sh_sp;
                regs[5] <= sh_t0;
                regs[6] <= sh_t1;
                regs[7] <= sh_t2;
            end
            // ── Priority 2: normal write-back ──
            // When shadow_restore is active, skip write to registers already
            // restored (avoids double-write to same register in same cycle).
            if (reg_write && rd != 5'b0) begin
                if (!shadow_restore ||
                    (rd != 5'd1 && rd != 5'd2 && rd != 5'd5 &&
                     rd != 5'd6 && rd != 5'd7))
                    regs[rd] <= write_data;
            end
        end
    end
//read1,read2
    assign read_data1 = (rs1 == 5'b0) ? 32'b0 : regs[rs1];
    assign read_data2 = (rs2 == 5'b0) ? 32'b0 : regs[rs2];
    assign debug_data = (debug_index == 5'b0) ? 32'b0 : regs[debug_index];
    // ── Key register values exposed for shadow capture ──
    assign x1_val = regs[1];
    assign x2_val = regs[2];
    assign x5_val = regs[5];
    assign x6_val = regs[6];
    assign x7_val = regs[7];
endmodule
