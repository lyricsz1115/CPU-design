module imem #(
    parameter MEM_WORDS = 256,
    parameter INIT_FILE = "program/sum.mem"
)(
    input wire [31:0] addr,
    output wire [31:0] inst
);
    reg [31:0] mem [0:MEM_WORDS-1];

    initial begin
        $readmemh(INIT_FILE, mem);
    end

    assign inst = mem[addr[31:2]];
endmodule
