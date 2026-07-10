module io_bus #(
    parameter MEM_WORDS = 256
)(
    input wire clk,
    input wire rst,
    input wire mem_read,
    input wire mem_write,
    input wire [31:0] addr,
    input wire [31:0] write_data,
    input wire [7:0] sw,
    input wire [31:0] cycle_count,
    input wire [31:0] instret_count,
    input wire [31:0] stall_count,
    input wire [31:0] flush_count,
    output reg [31:0] read_data,
    output wire [31:0] debug_dmem0,
    output wire [7:0] led
);
    localparam IO_LED_ADDR      = 32'h1000_0000;
    localparam IO_SW_ADDR       = 32'h1000_0004;
    localparam IO_CYCLE_ADDR    = 32'h1000_0010;
    localparam IO_INSTRET_ADDR  = 32'h1000_0014;
    localparam IO_STALL_ADDR    = 32'h1000_0018;
    localparam IO_FLUSH_ADDR    = 32'h1000_001c;

    reg [31:0] mem [0:MEM_WORDS-1];
    reg [7:0] led_reg;
    integer i;

    wire data_mem_selected = (addr[31:10] == 22'b0);
    wire [7:0] word_addr = addr[9:2];

    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1) begin
            mem[i] = 32'b0;
        end
        led_reg = 8'b0;
    end

    always @(*) begin
        if (mem_read) begin
            if (data_mem_selected) begin
                read_data = mem[word_addr];
            end else begin
                case (addr)
                    IO_LED_ADDR:     read_data = {24'b0, led_reg};
                    IO_SW_ADDR:      read_data = {24'b0, sw};
                    IO_CYCLE_ADDR:   read_data = cycle_count;
                    IO_INSTRET_ADDR: read_data = instret_count;
                    IO_STALL_ADDR:   read_data = stall_count;
                    IO_FLUSH_ADDR:   read_data = flush_count;
                    default:         read_data = 32'b0;
                endcase
            end
        end else begin
            read_data = 32'b0;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            led_reg <= 8'b0;
            for (i = 0; i < MEM_WORDS; i = i + 1) begin
                mem[i] <= 32'b0;
            end
        end else if (mem_write) begin
            if (data_mem_selected) begin
                mem[word_addr] <= write_data;
            end else if (addr == IO_LED_ADDR) begin
                led_reg <= write_data[7:0];
            end
        end
    end

    assign debug_dmem0 = mem[0];
    assign led = (led_reg != 8'b0) ? led_reg : mem[0][7:0];
endmodule
