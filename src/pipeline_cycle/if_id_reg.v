module if_id_reg(
    input wire clk,
    input wire rst,
    input wire en,
    input wire flush,
    input wire [31:0] pc_in,
    input wire [31:0] inst_in,
    output reg [31:0] pc_out,
    output reg [31:0] inst_out
);
    always @(posedge clk or posedge rst) begin
        if (rst || flush) begin
            pc_out <= 32'b0;
            inst_out <= 32'h00000013;
        end else if (en) begin
            pc_out <= pc_in;
            inst_out <= inst_in;
        end
    end
endmodule
