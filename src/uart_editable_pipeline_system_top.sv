`timescale 1ns / 1ps

module uart_editable_pipeline_system_top #(
    parameter integer UART_CLK_HZ = 100_000_000,
    parameter integer UART_BAUD = 115_200
) (
    input  logic       clk,
    input  logic       rst_btn,
    input  logic [7:0] sw,
    input  logic       btn_write,
    input  logic       btn_next,
    input  logic       btn_clear,
    input  logic       btn_run,
    input  logic       btn_display_mode,
    input  logic       uart_rx,
    output logic       uart_tx,
    output logic [7:0] led,
    output logic       mode_led_imem,
    output logic       mode_led_dmem,
    output logic       mode_led_reg,
    output logic [7:0] seg_an,
    output logic [7:0] seg_out
);
    localparam logic [1:0] DISPLAY_IMEM = 2'd0;
    localparam logic [1:0] DISPLAY_DMEM = 2'd1;
    localparam logic [1:0] DISPLAY_REG  = 2'd2;
    localparam integer BUTTON_DEBOUNCE_CYCLES = 1_000_000;
    localparam integer DISPLAY_DEBOUNCE_CYCLES = 1_000_000;

    logic [7:0] uart_rx_data;
    logic uart_rx_valid;
    logic uart_framing_error;
    logic packet_valid;
    logic packet_crc_error;
    logic packet_timeout_error;
    logic [7:0] request_command;
    logic [7:0] request_sequence;
    logic [15:0] request_address;
    logic [31:0] request_data;
    logic [7:0] request_flags;

    logic response_valid;
    logic response_ready;
    logic [7:0] response_status;
    logic [7:0] response_sequence;
    logic [15:0] response_address;
    logic [7:0] response_detail;
    logic response_busy;
    logic response_sent;

    logic run_mode;
    logic uart_run_mode;
    logic manual_run_mode;
    logic uart_run_mode_d;
    logic manual_run_mode_d;

    logic imem_write_enable;
    logic [31:0] imem_write_addr;
    logic [31:0] imem_write_data;
    logic uart_imem_write_enable;
    logic [31:0] uart_imem_write_addr;
    logic [31:0] uart_imem_write_data;
    logic manual_imem_write_enable;
    logic [31:0] manual_imem_write_addr;
    logic [31:0] manual_imem_write_data;
    logic [7:0] manual_instr_index;
    logic [1:0] manual_byte_index;
    logic [31:0] manual_current_word;

    logic [1:0] loader_state;
    logic [8:0] expected_words;
    logic [8:0] received_words;
    logic loader_error_seen;
    logic transport_error_seen;

    logic stall_debug;
    logic flush_debug;
    logic predict_taken_debug;
    logic inst_valid_debug;
    logic [31:0] debug_cycle_count;
    logic [31:0] debug_instret_count;
    logic [31:0] debug_stall_count;
    logic [31:0] debug_flush_count;
    logic [31:0] debug_cache_access_count;
    logic [31:0] debug_cache_hit_count;
    logic [31:0] debug_cache_miss_count;
    logic [31:0] debug_pc;
    logic [31:0] cpu_debug_dmem0;
    logic [31:0] cpu_debug_dmem1;
    logic [31:0] debug_imem_data;
    logic [31:0] debug_reg_data;
    logic [31:0] debug_dmem_data;

    logic bus_mem_read;
    logic bus_mem_write;
    logic [31:0] bus_addr;
    logic [31:0] bus_write_data;
    logic [31:0] bus_read_data;
    logic [31:0] bus_debug_dmem0;
    logic [7:0] bus_led;
    logic [1:0] display_mode;
    logic btn_display_meta;
    logic btn_display_sync;
    logic btn_display_state;
    logic btn_display_state_d;
    logic [19:0] display_debounce_count;
    logic [24:0] blink_count;
    logic [31:0] seg_display_value;

    wire cpu_rst = rst_btn | ~run_mode;
    wire [7:0] uart_load_display = {
        loader_error_seen | transport_error_seen,
        response_busy,
        loader_state,
        received_words[3:0]
    };
    wire [7:0] manual_load_addr_display = {manual_instr_index[3:0], manual_byte_index, 2'b00};
    wire [7:0] manual_load_display = blink_count[24] ? sw : manual_load_addr_display;
    wire manual_loader_active = (manual_instr_index != 8'd0) ||
                                (manual_byte_index != 2'd0) ||
                                (manual_current_word != 32'd0) ||
                                manual_imem_write_enable;
    wire [7:0] load_display = manual_loader_active ? manual_load_display : uart_load_display;
    wire [7:0] run_display = (bus_led != 8'd0) ? bus_led :
                             ((cpu_debug_dmem0[7:0] != 8'd0) ? cpu_debug_dmem0[7:0] :
                              {1'b1, debug_pc[6:0]});
    wire display_mode_pulse = btn_display_state & ~btn_display_state_d;
    wire uart_loader_stop_request = packet_valid &&
                                    ((request_command == 8'h01) ||
                                     (request_command == 8'h04));
    wire uart_run_start = uart_run_mode & ~uart_run_mode_d;
    wire uart_run_stop = ~uart_run_mode & uart_run_mode_d;
    wire manual_run_start = manual_run_mode & ~manual_run_mode_d;
    wire manual_run_stop = ~manual_run_mode & manual_run_mode_d;

    assign imem_write_enable = uart_imem_write_enable | manual_imem_write_enable;
    assign imem_write_addr = uart_imem_write_enable ? uart_imem_write_addr :
                                                   manual_imem_write_addr;
    assign imem_write_data = uart_imem_write_enable ? uart_imem_write_data :
                                                   manual_imem_write_data;

    uart_rx_byte #(
        .CLK_HZ(UART_CLK_HZ),
        .BAUD(UART_BAUD)
    ) u_uart_rx_byte (
        .clk(clk),
        .reset(rst_btn),
        .rx(uart_rx),
        .data(uart_rx_data),
        .valid(uart_rx_valid),
        .framing_error(uart_framing_error)
    );

    uart_program_packet_rx #(
        .CLK_HZ(UART_CLK_HZ)
    ) u_program_packet_rx (
        .clk(clk),
        .reset(rst_btn),
        .rx_data(uart_rx_data),
        .rx_valid(uart_rx_valid),
        .rx_framing_error(uart_framing_error),
        .packet_valid(packet_valid),
        .crc_error(packet_crc_error),
        .timeout_error(packet_timeout_error),
        .command(request_command),
        .sequence_number(request_sequence),
        .word_address(request_address),
        .word_data(request_data),
        .flags(request_flags)
    );

    uart_program_loader u_program_loader (
        .clk(clk),
        .reset(rst_btn),
        .packet_valid(packet_valid),
        .packet_crc_error(packet_crc_error),
        .request_command(request_command),
        .request_sequence(request_sequence),
        .request_address(request_address),
        .request_data(request_data),
        .request_flags(request_flags),
        .response_valid(response_valid),
        .response_ready(response_ready),
        .response_status(response_status),
        .response_sequence(response_sequence),
        .response_address(response_address),
        .response_detail(response_detail),
        .run_mode(uart_run_mode),
        .imem_write_enable(uart_imem_write_enable),
        .imem_write_addr(uart_imem_write_addr),
        .imem_write_data(uart_imem_write_data),
        .loader_state(loader_state),
        .expected_words(expected_words),
        .received_words(received_words),
        .error_seen(loader_error_seen)
    );

    instr_loader #(
        .DEBOUNCE_CYCLES(BUTTON_DEBOUNCE_CYCLES)
    ) u_manual_loader (
        .clk(clk),
        .rst(rst_btn),
        .sw(sw),
        .btn_write(btn_write),
        .btn_next(btn_next),
        .btn_clear(btn_clear),
        .btn_run(btn_run),
        .run_mode(manual_run_mode),
        .imem_write_enable(manual_imem_write_enable),
        .imem_write_addr(manual_imem_write_addr),
        .imem_write_data(manual_imem_write_data),
        .instr_index(manual_instr_index),
        .byte_index(manual_byte_index),
        .current_word(manual_current_word)
    );

    uart_response_packet_tx #(
        .CLK_HZ(UART_CLK_HZ),
        .BAUD(UART_BAUD)
    ) u_response_packet_tx (
        .clk(clk),
        .reset(rst_btn),
        .response_valid(response_valid),
        .response_ready(response_ready),
        .status(response_status),
        .sequence_number(response_sequence),
        .word_address(response_address),
        .detail(response_detail),
        .tx(uart_tx),
        .busy(response_busy),
        .sent_pulse(response_sent)
    );

    pipeline_cpu_top #(
        .INIT_FILE("sum.mem"),
        .USE_INIT_FILE(0),
        .PROGRAM_ID(255),
        .ENABLE_IMEM_WRITE(1),
        .USE_EXTERNAL_DATA_BUS(1)
    ) u_cpu (
        .clk(clk),
        .rst(cpu_rst),
        .imem_write_enable(imem_write_enable),
        .imem_write_addr(imem_write_addr),
        .imem_write_data(imem_write_data),
        .debug_imem_index(sw),
        .debug_dmem_index(sw),
        .debug_reg_index(sw[4:0]),
        .external_read_data(bus_read_data),
        .external_mem_read(bus_mem_read),
        .external_mem_write(bus_mem_write),
        .external_addr(bus_addr),
        .external_write_data(bus_write_data),
        .stall_debug(stall_debug),
        .flush_debug(flush_debug),
        .predict_taken_debug(predict_taken_debug),
        .inst_valid_debug(inst_valid_debug),
        .debug_cycle_count(debug_cycle_count),
        .debug_instret_count(debug_instret_count),
        .debug_stall_count(debug_stall_count),
        .debug_flush_count(debug_flush_count),
        .debug_cache_access_count(debug_cache_access_count),
        .debug_cache_hit_count(debug_cache_hit_count),
        .debug_cache_miss_count(debug_cache_miss_count),
        .debug_pc(debug_pc),
        .debug_dmem0(cpu_debug_dmem0),
        .debug_dmem1(cpu_debug_dmem1),
        .debug_dmem_data(debug_dmem_data),
        .debug_imem_data(debug_imem_data),
        .debug_reg_data(debug_reg_data)
    );

    io_bus u_io_bus (
        .clk(clk),
        .rst(cpu_rst),
        .mem_read(bus_mem_read),
        .mem_write(bus_mem_write),
        .addr(bus_addr),
        .write_data(bus_write_data),
        .sw(sw),
        .cycle_count(debug_cycle_count),
        .instret_count(debug_instret_count),
        .stall_count(debug_stall_count),
        .flush_count(debug_flush_count),
        .debug_index(sw),
        .read_data(bus_read_data),
        .debug_dmem0(bus_debug_dmem0),
        .debug_data(),
        .led(bus_led)
    );

    seg7_hex_display u_seg7_display (
        .clk(clk),
        .rst(rst_btn),
        .value(seg_display_value),
        .seg_an(seg_an),
        .seg_out(seg_out)
    );

    always_ff @(posedge clk or posedge rst_btn) begin
        if (rst_btn) begin
            btn_display_meta <= 1'b0;
            btn_display_sync <= 1'b0;
            btn_display_state <= 1'b0;
            btn_display_state_d <= 1'b0;
            display_debounce_count <= 20'd0;
        end else begin
            btn_display_meta <= btn_display_mode;
            btn_display_sync <= btn_display_meta;
            btn_display_state_d <= btn_display_state;

            if (btn_display_sync == btn_display_state) begin
                display_debounce_count <= 20'd0;
            end else if (display_debounce_count >= DISPLAY_DEBOUNCE_CYCLES - 1) begin
                btn_display_state <= btn_display_sync;
                display_debounce_count <= 20'd0;
            end else begin
                display_debounce_count <= display_debounce_count + 20'd1;
            end
        end
    end

    always_ff @(posedge clk or posedge rst_btn) begin
        if (rst_btn) begin
            display_mode <= DISPLAY_IMEM;
        end else if (display_mode_pulse) begin
            display_mode <= (display_mode == DISPLAY_REG) ? DISPLAY_IMEM :
                            display_mode + 2'd1;
        end
    end

    always_ff @(posedge clk or posedge rst_btn) begin
        if (rst_btn) begin
            run_mode <= 1'b0;
            uart_run_mode_d <= 1'b0;
            manual_run_mode_d <= 1'b0;
        end else begin
            uart_run_mode_d <= uart_run_mode;
            manual_run_mode_d <= manual_run_mode;

            if (uart_run_start || manual_run_start) begin
                run_mode <= 1'b1;
            end
            if (uart_loader_stop_request || btn_clear || uart_run_stop || manual_run_stop) begin
                run_mode <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk or posedge rst_btn) begin
        if (rst_btn) begin
            blink_count <= 25'd0;
        end else begin
            blink_count <= blink_count + 25'd1;
        end
    end

    always_comb begin
        case (display_mode)
            DISPLAY_IMEM: seg_display_value = debug_imem_data;
            DISPLAY_DMEM: seg_display_value = debug_dmem_data;
            DISPLAY_REG:  seg_display_value = debug_reg_data;
            default:      seg_display_value = debug_imem_data;
        endcase
    end

    assign mode_led_imem = (display_mode == DISPLAY_IMEM);
    assign mode_led_dmem = (display_mode == DISPLAY_DMEM);
    assign mode_led_reg = (display_mode == DISPLAY_REG);

    always_ff @(posedge clk) begin
        if (rst_btn) begin
            transport_error_seen <= 1'b0;
        end else if (packet_valid && (request_command == 8'h01)) begin
            transport_error_seen <= 1'b0;
        end else if (uart_framing_error || packet_timeout_error) begin
            transport_error_seen <= 1'b1;
        end
    end

    always_comb begin
        led = run_mode ? run_display : load_display;
    end
endmodule
