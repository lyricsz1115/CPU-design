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
