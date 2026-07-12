module imem #(
    parameter MEM_WORDS = 256,
    parameter INIT_FILE = "sum.mem",
    parameter USE_INIT_FILE = 1,
    parameter PROGRAM_ID = 0
)(
    input wire [31:0] addr,
    input wire clk,
    input wire write_enable,
    input wire [31:0] write_addr,
    input wire [31:0] write_data,
    input wire [7:0] debug_index,
    output wire [31:0] inst,
    output wire [31:0] debug_data
);
    reg [31:0] mem [0:MEM_WORDS-1];
    integer i;

    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1) begin
            mem[i] = 32'h00000013;
            //imm[11:0]   rs1  f3  rd   ITYPE
        end

        case (PROGRAM_ID)
            0: begin // sum.mem, result dmem[0] = 55
                mem[0] = 32'h00000093;
                mem[1] = 32'h00100113;
                mem[2] = 32'h00b00193;
                mem[3] = 32'h002080b3;
                mem[4] = 32'h00110113;
                mem[5] = 32'h00310463;
                mem[6] = 32'hff5ff06f;
                mem[7] = 32'h00102023;
                mem[8] = 32'h0000006f;
            end
            1: begin // io_led.mem, result led = 8'h55
                mem[0] = 32'h100000b7;
                mem[1] = 32'h05500113;
                mem[2] = 32'h0020a023;
                mem[3] = 32'h0000006f;
            end
            2: begin // pipeline_nop.mem, result dmem[0] = 2
                mem[0] = 32'h00100093;
                mem[1] = 32'h00000013;
                mem[2] = 32'h00000013;
                mem[3] = 32'h00108133;
                mem[4] = 32'h00000013;
                mem[5] = 32'h00000013;
                mem[6] = 32'h00202023;
                mem[7] = 32'h0000006f;
            end
            3: begin // hazard.mem, result dmem[0] = 5
                mem[0] = 32'h00500093;
                mem[1] = 32'h00300113;
                mem[2] = 32'h002081b3;
                mem[3] = 32'h40218233;
                mem[4] = 32'h00402023;
                mem[5] = 32'h0000006f;
            end
            4: begin // load_use.mem, result dmem[1] = 200
                mem[0] = 32'h06400093;
                mem[1] = 32'h00102023;
                mem[2] = 32'h00002103;
                mem[3] = 32'h002101b3;
                mem[4] = 32'h00302223;
                mem[5] = 32'h0000006f;
            end
            5: begin // branch.mem, result dmem[0] = 7
                mem[0] = 32'h00100093;
                mem[1] = 32'h00100113;
                mem[2] = 32'h00208463;
                mem[3] = 32'h06300193;
                mem[4] = 32'h00700193;
                mem[5] = 32'h00302023;
                mem[6] = 32'h0000006f;
            end
            6: begin // branch_predict.mem, backward beq predicted taken, result dmem[0] = 1
                mem[0] = 32'h00100093;
                mem[1] = 32'h00100113;
                mem[2] = 32'h00102023;
                mem[3] = 32'hfe208ee3;
            end
            7: begin // mul_div.mem, dmem[0]=60 dmem[1]=6 dmem[2]=2 dmem[3]=20 dmem[4]=48 dmem[5]=56
                mem[0]  = 32'h01400093;
                mem[1]  = 32'h00300113;
                mem[2]  = 32'h022081b3;
                mem[3]  = 32'h0220c233;
                mem[4]  = 32'h0220e2b3;
                mem[5]  = 32'h0ff0f313;
                mem[6]  = 32'h00411393;
                mem[7]  = 32'h0083e413;
                mem[8]  = 32'h00302023;
                mem[9]  = 32'h00402223;
                mem[10] = 32'h00502423;
                mem[11] = 32'h00602623;
                mem[12] = 32'h00702823;
                mem[13] = 32'h00802a23;
                mem[14] = 32'h0000006f;
            end
            8: begin // cache_board_demo.mem, mem[0]=0x55, access/hit/miss=6/4/2
                mem[0] = 32'h05500093;
                mem[1] = 32'h00102023;
                mem[2] = 32'h00002103;
                mem[3] = 32'h00402183;
                mem[4] = 32'h00002203;
                mem[5] = 32'h00802283;
                mem[6] = 32'h00c02303;
                mem[7] = 32'h100003b7;
                mem[8] = 32'h0013a023;
                mem[9] = 32'h0000006f;
            end
            9: begin // trap_test_board.mem — 上板可见中断测试
                // Phase 1: LED=0x0F ~3s → Phase 2: LED=0xF0 ~3s
                // Phase 3: CSR setup → Phase 4: Shadow values + mtimecmp
                // Phase 5: Main loop (LUI+ADDI inside loop → x28 immune to ISR overwrite)
                // ISR @0x100: LED=0xFF ~1s then MRET
                mem[  0] = 32'h10000F37;
                mem[  1] = 32'h00F00F93;
                mem[  2] = 32'h01FF2023;
                mem[  3] = 32'h10000E37;
                mem[  4] = 32'h100E0E13;
                mem[  5] = 32'h000E2E83;
                mem[  6] = 32'h11E1AFB7;
                mem[  7] = 32'h300F8F93;
                mem[  8] = 32'h01FE8EB3;
                mem[  9] = 32'h000E2F83;
                mem[ 10] = 32'hFFDFEEE3;
                mem[ 11] = 32'h0F000F93;
                mem[ 12] = 32'h01FF2023;
                mem[ 13] = 32'h10000E37;
                mem[ 14] = 32'h100E0E13;
                mem[ 15] = 32'h000E2E83;
                mem[ 16] = 32'h11E1AFB7;
                mem[ 17] = 32'h300F8F93;
                mem[ 18] = 32'h01FE8EB3;
                mem[ 19] = 32'h000E2F83;
                mem[ 20] = 32'hFFDFEEE3;
                mem[ 21] = 32'h10000F93;
                mem[ 22] = 32'h305F9073;
                mem[ 23] = 32'h30400F93;
                mem[ 24] = 32'h08000E93;
                mem[ 25] = 32'h304E9073;
                mem[ 26] = 32'h30000F93;
                mem[ 27] = 32'h00800E93;
                mem[ 28] = 32'h300E9073;
                mem[ 29] = 32'h0A100093;
                mem[ 30] = 32'h0B500293;
                mem[ 31] = 32'h0C600313;
                mem[ 32] = 32'h0D700393;
                mem[ 33] = 32'h10000E37;
                mem[ 34] = 32'h100E0E13;
                mem[ 35] = 32'h000E2F83;
                mem[ 36] = 32'h02FAFEB7;
                mem[ 37] = 32'h080E8E93;
                mem[ 38] = 32'h01FE8FB3;
                mem[ 39] = 32'h004E0E13;
                mem[ 40] = 32'h01FE2023;
                // Phase 5: Main loop — LUI+ADDI inside loop re-inits t3 each iteration
                mem[ 41] = 32'h10000F37;  // LUI  t5, 0x10000  — LED base (outside loop)
                mem[ 42] = 32'h10000E37;  // LOOP: LUI  t3, 0x10000
                mem[ 43] = 32'h100E0E13;  // ADDI t3, t3, 0x100 — t3=MTIME (inside loop!)
                mem[ 44] = 32'h000E2F83;  // LW   t6, 0(t3)    — t6 = mtime
                mem[ 45] = 32'h018FDF93;  // SRLI t6, t6, 24   — t6 = mtime[31:24]
                mem[ 46] = 32'h01FF2023;  // SW   t6, 0(t5)    — LED = mtime[31:24]
                mem[ 47] = 32'h000E2F83;  // delay padding
                mem[ 48] = 32'h000E2F83;
                mem[ 49] = 32'h000E2F83;
                mem[ 50] = 32'hFE1FF06F;  // JAL  x0, LOOP     — offset = -32 (LOOP at mem[42])
                mem[ 51] = 32'h00000013;
                mem[ 52] = 32'h00000013;
                mem[ 53] = 32'h00000013;
                mem[ 54] = 32'h00000013;
                mem[ 55] = 32'h00000013;
                mem[ 56] = 32'h00000013;
                mem[ 57] = 32'h00000013;
                mem[ 58] = 32'h00000013;
                mem[ 59] = 32'h00000013;
                mem[ 60] = 32'h00000013;
                mem[ 61] = 32'h00000013;
                mem[ 62] = 32'h00000013;
                mem[ 63] = 32'h00000013;
                mem[ 64] = 32'h10000F37;  // === ISR at 0x100 ===
                mem[ 65] = 32'h0FF00E93;
                mem[ 66] = 32'h01DF2023;  // LED = 0xFF !!
                mem[ 67] = 32'h01D02023;
                mem[ 68] = 32'h10000E37;
                mem[ 69] = 32'h100E0E13;
                mem[ 70] = 32'h000E2E83;
                mem[ 71] = 32'h05F5EFB7;  // hi20(100M ticks = 1s)
                mem[ 72] = 32'h100F8F93;  // lo12(100M ticks)
                mem[ 73] = 32'h01FE8EB3;
                mem[ 74] = 32'h000E2F83;
                mem[ 75] = 32'hFFDFEEE3;
                mem[ 76] = 32'h00102223;
                mem[ 77] = 32'h00502423;
                mem[ 78] = 32'h00602623;
                mem[ 79] = 32'h00702823;
                mem[ 80] = 32'h0DE00093;
                mem[ 81] = 32'h0AD00293;
                mem[ 82] = 32'h0BE00313;
                mem[ 83] = 32'h0EF00393;
                mem[ 84] = 32'h10000E37;
                mem[ 85] = 32'h104E0E13;
                mem[ 86] = 32'h7FFFFFB7;
                mem[ 87] = 32'h01FE2023;
                mem[ 88] = 32'h30200073;  // MRET — shadow restore x1,x5,x6,x7
            end            10: begin // blink.mem — 纯 LED 闪烁 (无中断, 最简验证)
                mem[0] = 32'h100002B7;  // lui  x5, 0x10000      — x5 = 0x10000000 (LED)
                mem[1] = 32'h00000313;  // addi x6, x0, 0        — x6 = 0
                mem[2] = 32'h00130313;  // addi x6, x6, 1        — LOOP: x6++
                mem[3] = 32'h0062A023;  // sw   x6, 0(x5)        — LED = x6
                mem[4] = 32'hFF9FF06F;  // jal  x0, -8           — 跳回 LOOP (PC+4)
            end
            11: begin // trap_inspect — 中断功能内存检查测试
                // 简短预置: LED=0xBB if loaded via PROGRAM_ID (fallback)
                // Full program loaded via UART or $readmemh("trap_inspect_board.mem")
                mem[0] = 32'h10000FB7;  // lui  x31, 0x10000    — t6 = 0x10000000 (LED base)
                mem[1] = 32'h0BB00E93;  // addi x29, x0, 0xBB   — t4 = 0xBB
                mem[2] = 32'h01DFA023;  // sw   x29, 0(x31)     — LED = 0xBB
                mem[3] = 32'h0000006F;  // jal  x0, 0            — infinite loop
            end
        endcase
//在仿真中使用$readmemh函数从指定的初始化文件中读取内存内容，并将其加载到内存数组中。
        if (USE_INIT_FILE) begin
            $readmemh(INIT_FILE, mem);
        end
    end
//
    always @(posedge clk) begin
        if (write_enable) begin
            mem[write_addr[31:2]] <= write_data;
        end
    end

    assign inst = mem[addr[31:2]];
    assign debug_data = mem[debug_index];
endmodule
