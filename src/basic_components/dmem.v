module dmem #(
    parameter MEM_WORDS = 256
)(
    input wire clk,
    input wire mem_read,
    input wire mem_write,
    input wire [31:0] addr,
    input wire [31:0] write_data,
    input wire [7:0] debug_index,
    output wire [31:0] read_data,
    output wire [31:0] debug_data
);
    reg [31:0] mem [0:MEM_WORDS-1];
    integer i;

    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1) begin
            mem[i] = 32'b0;
        end
    end

    assign read_data = mem_read ? mem[addr[31:2]] : 32'b0;
    assign debug_data = mem[debug_index];

    always @(posedge clk) begin
        if (mem_write) begin
            mem[addr[31:2]] <= write_data;
        end
    end
endmodule
