module instr_loader #(
    parameter ADDR_WIDTH = 8,
    parameter DEBOUNCE_CYCLES = 1
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
    localparam DEBOUNCE_WIDTH = 20;

    reg [3:0] btn_meta;
    reg [3:0] btn_sync;
    reg [3:0] btn_state;
    reg [3:0] btn_state_d;
    reg [DEBOUNCE_WIDTH-1:0] debounce_count [0:3];
    integer i;

    wire [3:0] btn_raw = {btn_run, btn_clear, btn_next, btn_write};
    wire write_pulse = btn_state[0] & ~btn_state_d[0];
    wire next_pulse = btn_state[1] & ~btn_state_d[1];
    wire clear_pulse = btn_state[2] & ~btn_state_d[2];
    wire run_pulse = btn_state[3] & ~btn_state_d[3];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            btn_meta <= 4'b0;
            btn_sync <= 4'b0;
            btn_state <= 4'b0;
            btn_state_d <= 4'b0;
            for (i = 0; i < 4; i = i + 1) begin
                debounce_count[i] <= {DEBOUNCE_WIDTH{1'b0}};
            end
        end else begin
            btn_meta <= btn_raw;
            btn_sync <= btn_meta;
            btn_state_d <= btn_state;

            for (i = 0; i < 4; i = i + 1) begin
                if (btn_sync[i] == btn_state[i]) begin
                    debounce_count[i] <= {DEBOUNCE_WIDTH{1'b0}};
                end else if (debounce_count[i] >= DEBOUNCE_CYCLES - 1) begin
                    btn_state[i] <= btn_sync[i];
                    debounce_count[i] <= {DEBOUNCE_WIDTH{1'b0}};
                end else begin
                    debounce_count[i] <= debounce_count[i] + {{(DEBOUNCE_WIDTH-1){1'b0}}, 1'b1};
                end
            end
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
