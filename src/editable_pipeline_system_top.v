module editable_pipeline_system_top #(
    parameter DEBOUNCE_CYCLES = 1000000
)(
    input wire clk,
    input wire rst_btn,
    input wire [8:0] sw,
    input wire btn_write,
    input wire btn_next,
    input wire btn_clear,
    input wire btn_run,
    output wire [7:0] led,
    output wire [7:0] seg_an,
    output wire [7:0] seg_out
);
    wire run_mode;
    wire imem_write_enable;
    wire [31:0] imem_write_addr;
    wire [31:0] imem_write_data;
    wire [7:0] instr_index;
    wire [1:0] byte_index;
    wire [31:0] current_word;

    wire stall_debug;
    wire flush_debug;
    wire predict_taken_debug;
    wire inst_valid_debug;
    wire [31:0] debug_cycle_count;
    wire [31:0] debug_instret_count;
    wire [31:0] debug_stall_count;
    wire [31:0] debug_flush_count;
    wire [31:0] debug_cache_access_count;
    wire [31:0] debug_cache_hit_count;
    wire [31:0] debug_cache_miss_count;
    wire [31:0] debug_pc;
    wire [31:0] cpu_debug_dmem0;
    wire [31:0] cpu_debug_dmem1;
    wire [31:0] cpu_debug_dmem_data;
    wire [31:0] debug_imem_data;
    wire [31:0] debug_reg_data;

    wire bus_mem_read;
    wire bus_mem_write;
    wire [31:0] bus_addr;
    wire [31:0] bus_write_data;
    wire [31:0] bus_read_data;
    wire [31:0] bus_debug_dmem0;
    wire [7:0] bus_led;

    // ── Trap timer + interrupt ──
    wire        mtimecmp_mmio_write;
    wire [31:0] mtimecmp_mmio_wdata;
    wire [31:0] mtime_mmio_val;
    wire [31:0] mtimecmp_mmio_val;
    wire        trap_taken;
    wire        irq_external;
    wire        irq_external_ack;
    reg         irq_external_latched;

    // ── Button synchronizer + debounce for btn_next ──
    // Mechanical button bounces for 1–10 ms. At 100 MHz a raw edge detector
    // generates thousands of spurious pulses per press, which breaks single-step.
    // Solution: 2-FF synchronizer → saturation counter → stable output.
    reg  [1:0]  btn_sync;               // 2-FF synchronizer (metastability)
    reg  [19:0] btn_db_cnt;             // debounce counter (0 … 1_000_000)
    reg         btn_db;                 // debounced / stable btn_next value
    reg         btn_db_d;               // delayed copy for edge detection
    wire        btn_db_posedge = btn_db && !btn_db_d;   // clean single-cycle pulse

    // ── Debug single-step ──
    wire        debug_mode = sw[8];       // sw[8]=1 → debug mode
    reg         debug_frozen;             // latch: auto-break on trap_taken
    reg         trap_taken_d;             // trap_taken edge detect
    wire        trap_taken_posedge = trap_taken && !trap_taken_d;

    // In debug mode the CPU is frozen by default. Each debounced S2 press
    // releases one clock so the PC can be observed step by step.
    wire        debug_stall = debug_mode && run_mode && !btn_db_posedge;

    reg [24:0] blink_count;
    reg [7:0] run_display;

    wire cpu_rst = rst_btn | ~run_mode;
    wire [7:0] load_addr_display = {instr_index[3:0], byte_index, 2'b00};
    wire [7:0] load_display = blink_count[24] ? sw[7:0] : load_addr_display;
    wire [7:0] result_display = (bus_led != 8'b0) ? bus_led :
                                 ((cpu_debug_dmem0[7:0] != 8'b0) ? cpu_debug_dmem0[7:0] :
                                  {1'b1, debug_pc[6:0]});
    wire [31:0] seg_display_value = run_mode ?
        (debug_mode ? debug_pc : debug_reg_data) : debug_imem_data;

    instr_loader #(
        .DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)
    ) u_loader (
        .clk(clk),
        .rst(rst_btn),
        .sw(sw[7:0]),
        .btn_write(btn_write),
        .btn_next(btn_next),
        .btn_clear(btn_clear),
        .btn_run(btn_run),
        .run_mode(run_mode),
        .imem_write_enable(imem_write_enable),
        .imem_write_addr(imem_write_addr),
        .imem_write_data(imem_write_data),
        .instr_index(instr_index),
        .byte_index(byte_index),
        .current_word(current_word)
    );

    // ── External interrupt: debounced btn_next rising edge in run mode ──
    always @(posedge clk or posedge rst_btn) begin
        if (rst_btn) begin
            irq_external_latched <= 1'b0;
        end else begin
            if (!run_mode)
                irq_external_latched <= 1'b0;
            else if (irq_external_ack)
                irq_external_latched <= 1'b0;
            else if (!debug_mode && btn_db_posedge)
                irq_external_latched <= 1'b1;     // hold request until the CPU accepts it
        end
    end
    assign irq_external = irq_external_latched;

    // ════════════════════════════════════════════════════════════════
    // Button synchronizer + debounce state machine
    // ════════════════════════════════════════════════════════════════
    always @(posedge clk or posedge rst_btn) begin
        if (rst_btn) begin
            btn_sync   <= 2'b0;
            btn_db_cnt <= 20'b0;
            btn_db     <= 1'b0;
            btn_db_d   <= 1'b0;
        end else begin
            // 2-FF synchronizer
            btn_sync <= {btn_sync[0], btn_next};
            // Debounce: when synced output differs from stable value, count up.
            // On saturation (~10 ms @ 100 MHz) accept the new level and reset.
            // When synced output matches stable, hold counter at zero.
            if (btn_sync[1] != btn_db) begin
                if (btn_db_cnt == 20'd1_000_000) begin
                    btn_db     <= btn_sync[1];
                    btn_db_cnt <= 20'b0;
                end else begin
                    btn_db_cnt <= btn_db_cnt + 20'd1;
                end
            end else begin
                btn_db_cnt <= 20'b0;
            end
            // Edge detection on debounced signal
            btn_db_d <= btn_db;
        end
    end

    // ════════════════════════════════════════════════════════════════
    // Debug single-step state machine (sw[8] = 1)
    //
    // trap_taken is still tracked for diagnostics, but it no longer gates the
    // basic SW8/S2 single-step mode.
    // ════════════════════════════════════════════════════════════════
    always @(posedge clk or posedge rst_btn) begin
        if (rst_btn) begin
            debug_frozen  <= 1'b0;
            trap_taken_d  <= 1'b0;
        end else if (!debug_mode || !run_mode) begin
            debug_frozen  <= 1'b0;
            trap_taken_d  <= trap_taken;
        end else begin
            trap_taken_d <= trap_taken;
            if (trap_taken_posedge)
                debug_frozen <= 1'b1;
        end
    end

    pipeline_cpu_top #(
        .INIT_FILE("sum.mem"),
        .USE_INIT_FILE(0),
        .PROGRAM_ID(9),     // 9 = trap_test (timer interrupt test)
        .ENABLE_IMEM_WRITE(1),
        .USE_EXTERNAL_DATA_BUS(1),
        .ENABLE_DATA_CACHE(1),
        .CACHE_NUM_SETS(8),
        .CACHE_WORDS_PER_LINE(4)
    ) u_cpu (
        .clk(clk),
        .rst(cpu_rst),
        .imem_write_enable(imem_write_enable),
        .imem_write_addr(imem_write_addr),
        .imem_write_data(imem_write_data),
        .debug_imem_index(sw[7:0]),
        .debug_dmem_index(sw[7:0]),
        .debug_reg_index(sw[4:0]),
        .external_read_data(bus_read_data),
        .external_mem_read(bus_mem_read),
        .external_mem_write(bus_mem_write),
        .external_addr(bus_addr),
        .external_write_data(bus_write_data),
        .mtimecmp_mmio_write(mtimecmp_mmio_write),
        .mtimecmp_mmio_wdata(mtimecmp_mmio_wdata),
        .mtime_mmio_val(mtime_mmio_val),
        .mtimecmp_mmio_val(mtimecmp_mmio_val),
        .irq_external(irq_external),
        .irq_external_ack(irq_external_ack),
        .debug_stall(debug_stall),
        .trap_taken_out(trap_taken),
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
        .debug_dmem_data(cpu_debug_dmem_data),
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
        .sw(sw[7:0]),
        .cycle_count(debug_cycle_count),
        .instret_count(debug_instret_count),
        .stall_count(debug_stall_count),
        .flush_count(debug_flush_count),
        .debug_index(sw[7:0]),
        .read_data(bus_read_data),
        .debug_dmem0(bus_debug_dmem0),
        .debug_data(),
        .led(bus_led),
        .mtimecmp_write(mtimecmp_mmio_write),
        .mtimecmp_wdata(mtimecmp_mmio_wdata),
        .mtime_val(mtime_mmio_val),
        .mtimecmp_val(mtimecmp_mmio_val),
        .irq_external(irq_external)
    );

    seg7_hex_display u_seg7_display (
        .clk(clk),
        .rst(rst_btn),
        .value(seg_display_value),
        .seg_an(seg_an),
        .seg_out(seg_out)
    );

    always @(posedge clk or posedge rst_btn) begin
        if (rst_btn) begin
            blink_count <= 25'b0;
        end else begin
            blink_count <= blink_count + 25'd1;
        end
    end

    always @(*) begin
        case (sw[7:6])
            2'b00: run_display = result_display;
            2'b01: run_display = debug_cache_access_count[7:0];
            2'b10: run_display = debug_cache_hit_count[7:0];
            2'b11: run_display = debug_cache_miss_count[7:0];
            default: run_display = result_display;
        endcase
    end

    assign led = run_mode ? run_display : load_display;
endmodule
