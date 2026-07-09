module instr_loader #(
    parameter ADDR_WIDTH = 8
)(
    input wire clk,
    input wire rst,
    input wire [7:0] sw,
    input wire btn_write,
    input wire btn_next,
    input wire btn_clear,
    input wire btn_run,
    output reg run_mode,
    output reg imem_write_enable,
    output reg [31:0] imem_write_addr,
    output reg [31:0] imem_write_data,
    output reg [ADDR_WIDTH-1:0] instr_index,
    output reg [1:0] byte_index,
    output reg [31:0] current_word
);
    reg btn_write_d;
    reg btn_next_d;
    reg btn_clear_d;
    reg btn_run_d;

    wire write_pulse = btn_write & ~btn_write_d;
    wire next_pulse = btn_next & ~btn_next_d;
    wire clear_pulse = btn_clear & ~btn_clear_d;
    wire run_pulse = btn_run & ~btn_run_d;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            btn_write_d <= 1'b0;
            btn_next_d <= 1'b0;
            btn_clear_d <= 1'b0;
            btn_run_d <= 1'b0;
        end else begin
            btn_write_d <= btn_write;
            btn_next_d <= btn_next;
            btn_clear_d <= btn_clear;
            btn_run_d <= btn_run;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            run_mode <= 1'b0;
            imem_write_enable <= 1'b0;
            imem_write_addr <= 32'b0;
            imem_write_data <= 32'b0;
            instr_index <= {ADDR_WIDTH{1'b0}};
            byte_index <= 2'b0;
            current_word <= 32'b0;
        end else begin
            imem_write_enable <= 1'b0;

            if (clear_pulse) begin
                run_mode <= 1'b0;
                instr_index <= {ADDR_WIDTH{1'b0}};
                byte_index <= 2'b0;
                current_word <= 32'b0;
            end else if (run_pulse) begin
                run_mode <= 1'b1;
            end else if (!run_mode) begin
                if (next_pulse) begin
                    instr_index <= instr_index + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                    byte_index <= 2'b0;
                    current_word <= 32'b0;
                end else if (write_pulse) begin
                    case (byte_index)
                        2'd0: current_word[7:0] <= sw;
                        2'd1: current_word[15:8] <= sw;
                        2'd2: current_word[23:16] <= sw;
                        2'd3: current_word[31:24] <= sw;
                    endcase

                    if (byte_index == 2'd3) begin
                        imem_write_enable <= 1'b1;
                        imem_write_addr <= {22'b0, instr_index, 2'b00};
                        imem_write_data <= {sw, current_word[23:0]};
                        instr_index <= instr_index + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                        byte_index <= 2'b0;
                        current_word <= 32'b0;
                    end else begin
                        byte_index <= byte_index + 2'd1;
                    end
                end
            end
        end
    end
endmodule
