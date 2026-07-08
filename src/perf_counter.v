module perf_counter(
    input wire clk,
    input wire rst,
    input wire inst_valid,
    input wire stall,
    input wire flush,
    output reg [31:0] cycle_count,
    output reg [31:0] instret_count,
    output reg [31:0] stall_count,
    output reg [31:0] flush_count
);
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cycle_count <= 32'b0;
            instret_count <= 32'b0;
            stall_count <= 32'b0;
            flush_count <= 32'b0;
        end else begin
            cycle_count <= cycle_count + 32'd1;

            if (inst_valid) begin
                instret_count <= instret_count + 32'd1;
            end

            if (stall) begin
                stall_count <= stall_count + 32'd1;
            end

            if (flush) begin
                flush_count <= flush_count + 32'd1;
            end
        end
    end
endmodule
