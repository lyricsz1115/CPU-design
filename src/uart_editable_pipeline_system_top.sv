`timescale 1ns / 1ps

module uart_editable_pipeline_system_top #(
    parameter integer UART_CLK_HZ = 100_000_000,
    parameter integer UART_BAUD = 115_200
) (
    input  logic       clk,
    input  logic       rst_btn,
    input  logic [7:0] sw,
    input  logic       uart_rx,
    output logic       uart_tx,
    output logic [7:0] led
);
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
    logic imem_write_enable;
    logic [31:0] imem_write_addr;
    logic [31:0] imem_write_data;
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
    logic [31:0] debug_pc;
    logic [31:0] cpu_debug_dmem0;
    logic [31:0] cpu_debug_dmem1;

    logic bus_mem_read;
    logic bus_mem_write;
    logic [31:0] bus_addr;
    logic [31:0] bus_write_data;
    logic [31:0] bus_read_data;
    logic [31:0] bus_debug_dmem0;
    logic [7:0] bus_led;

    wire cpu_rst = rst_btn | ~run_mode;
    wire [7:0] load_display = {
        loader_error_seen | transport_error_seen,
        response_busy,
        loader_state,
        received_words[3:0]
    };
    wire [7:0] run_display = (bus_led != 8'd0) ? bus_led :
                             {1'b1, debug_pc[6:0]};

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
        .run_mode(run_mode),
        .imem_write_enable(imem_write_enable),
        .imem_write_addr(imem_write_addr),
        .imem_write_data(imem_write_data),
        .loader_state(loader_state),
        .expected_words(expected_words),
        .received_words(received_words),
        .error_seen(loader_error_seen)
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
        .debug_pc(debug_pc),
        .debug_dmem0(cpu_debug_dmem0),
        .debug_dmem1(cpu_debug_dmem1)
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
        .read_data(bus_read_data),
        .debug_dmem0(bus_debug_dmem0),
        .led(bus_led)
    );

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
