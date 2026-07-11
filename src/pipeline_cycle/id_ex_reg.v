module id_ex_reg(
    input wire clk,
    input wire rst,
    input wire en,
    input wire flush,
    input wire reg_write_in,
    input wire mem_to_reg_in,
    input wire mem_read_in,
    input wire mem_write_in,
    input wire branch_in,
    input wire jal_in,
    input wire alu_src_in,
    input wire [1:0] alu_op_in,
    input wire [31:0] pc_in,
    input wire [31:0] reg_data1_in,
    input wire [31:0] reg_data2_in,
    input wire [31:0] imm_in,
    input wire pred_taken_in,
    input wire [31:0] pred_target_in,
    input wire [4:0] rs1_in,
    input wire [4:0] rs2_in,
    input wire [4:0] rd_in,
    input wire [2:0] funct3_in,
    input wire [6:0] funct7_in,
    output reg reg_write_out,
    output reg mem_to_reg_out,
    output reg mem_read_out,
    output reg mem_write_out,
    output reg branch_out,
    output reg jal_out,
    output reg alu_src_out,
    output reg [1:0] alu_op_out,
    output reg [31:0] pc_out,
    output reg [31:0] reg_data1_out,
    output reg [31:0] reg_data2_out,
    output reg [31:0] imm_out,
    output reg pred_taken_out,
    output reg [31:0] pred_target_out,
    output reg [4:0] rs1_out,
    output reg [4:0] rs2_out,
    output reg [4:0] rd_out,
    output reg [2:0] funct3_out,
    output reg [6:0] funct7_out
);
    always @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            reg_write_out <= 1'b0;
            mem_to_reg_out <= 1'b0;
            mem_read_out <= 1'b0;
            mem_write_out <= 1'b0;
            branch_out <= 1'b0;
            jal_out <= 1'b0;
            alu_src_out <= 1'b0;
            alu_op_out <= 2'b00;
            pc_out <= 32'b0;
            reg_data1_out <= 32'b0;
            reg_data2_out <= 32'b0;
            imm_out <= 32'b0;
            pred_taken_out <= 1'b0;
            pred_target_out <= 32'b0;
            rs1_out <= 5'b0;
            rs2_out <= 5'b0;
            rd_out <= 5'b0;
            funct3_out <= 3'b0;
            funct7_out <= 7'b0;
        end else if (en) begin
            reg_write_out <= reg_write_in;
            mem_to_reg_out <= mem_to_reg_in;
            mem_read_out <= mem_read_in;
            mem_write_out <= mem_write_in;
            branch_out <= branch_in;
            jal_out <= jal_in;
            alu_src_out <= alu_src_in;
            alu_op_out <= alu_op_in;
            pc_out <= pc_in;
            reg_data1_out <= reg_data1_in;
            reg_data2_out <= reg_data2_in;
            imm_out <= imm_in;
            pred_taken_out <= pred_taken_in;
            pred_target_out <= pred_target_in;
            rs1_out <= rs1_in;
            rs2_out <= rs2_in;
            rd_out <= rd_in;
            funct3_out <= funct3_in;
            funct7_out <= funct7_in;
        end
    end
endmodule
