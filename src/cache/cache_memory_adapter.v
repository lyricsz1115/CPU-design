`timescale 1ns/1ps

module cache_memory_adapter #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input wire clk,
    input wire rst,

    input wire req_valid,
    output wire req_ready,
    input wire req_write,
    input wire [ADDR_WIDTH-1:0] req_addr,
    input wire [DATA_WIDTH-1:0] req_wdata,
    output wire resp_valid,
    output wire [DATA_WIDTH-1:0] resp_rdata,

    output wire backend_mem_read,
    output wire backend_mem_write,
    output wire [ADDR_WIDTH-1:0] backend_addr,
    output wire [DATA_WIDTH-1:0] backend_write_data,
    input wire [DATA_WIDTH-1:0] backend_read_data
);
    reg pending;
    reg [DATA_WIDTH-1:0] pending_read_data;

    assign req_ready = ~pending;
    assign resp_valid = pending;
    assign resp_rdata = pending_read_data;

    assign backend_mem_read = req_valid && req_ready && !req_write;
    assign backend_mem_write = req_valid && req_ready && req_write;
    assign backend_addr = req_addr;
    assign backend_write_data = req_wdata;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pending <= 1'b0;
            pending_read_data <= {DATA_WIDTH{1'b0}};
        end else if (pending) begin
            pending <= 1'b0;
        end else if (req_valid && req_ready) begin
            pending <= 1'b1;
            pending_read_data <= req_write ? {DATA_WIDTH{1'b0}} : backend_read_data;
        end
    end
endmodule
