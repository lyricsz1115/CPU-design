`timescale 1ns/1ps

module tb_data_cache;
    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;
    localparam NUM_SETS = 8;
    localparam WORDS_PER_LINE = 4;

    reg clk;
    reg rst;

    reg req_valid;
    wire req_ready;
    reg req_write;
    reg [ADDR_WIDTH-1:0] req_addr;
    reg [DATA_WIDTH-1:0] req_wdata;
    wire resp_valid;
    wire [DATA_WIDTH-1:0] resp_rdata;
    wire resp_hit;
    wire busy;

    wire mem_req_valid;
    wire mem_req_ready;
    wire mem_req_write;
    wire [ADDR_WIDTH-1:0] mem_req_addr;
    wire [DATA_WIDTH-1:0] mem_req_wdata;
    wire mem_resp_valid;
    wire [DATA_WIDTH-1:0] mem_resp_rdata;

    wire [31:0] access_count;
    wire [31:0] hit_count;
    wire [31:0] miss_count;

    integer i;
    integer pass_index;
    reg [7:0] lfsr;
    reg observed_hit;
    reg [31:0] observed_data;

    data_cache #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_SETS(NUM_SETS),
        .WORDS_PER_LINE(WORDS_PER_LINE)
    ) dut (
        .clk(clk),
        .rst(rst),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_write(req_write),
        .req_addr(req_addr),
        .req_wdata(req_wdata),
        .resp_valid(resp_valid),
        .resp_rdata(resp_rdata),
        .resp_hit(resp_hit),
        .busy(busy),
        .mem_req_valid(mem_req_valid),
        .mem_req_ready(mem_req_ready),
        .mem_req_write(mem_req_write),
        .mem_req_addr(mem_req_addr),
        .mem_req_wdata(mem_req_wdata),
        .mem_resp_valid(mem_resp_valid),
        .mem_resp_rdata(mem_resp_rdata),
        .access_count(access_count),
        .hit_count(hit_count),
        .miss_count(miss_count)
    );

    cache_memory_model #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_WORDS(1024),
        .RESPONSE_DELAY(2)
    ) u_memory (
        .clk(clk),
        .rst(rst),
        .req_valid(mem_req_valid),
        .req_ready(mem_req_ready),
        .req_write(mem_req_write),
        .req_addr(mem_req_addr),
        .req_wdata(mem_req_wdata),
        .resp_valid(mem_resp_valid),
        .resp_rdata(mem_resp_rdata)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task reset_cache;
        begin
            req_valid = 1'b0;
            req_write = 1'b0;
            req_addr = 32'b0;
            req_wdata = 32'b0;
            rst = 1'b1;
            repeat (3) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;
        end
    endtask

    task cache_read;
        input [ADDR_WIDTH-1:0] address;
        begin
            while (!req_ready) begin
                @(negedge clk);
            end

            req_valid = 1'b1;
            req_write = 1'b0;
            req_addr = address;
            req_wdata = {DATA_WIDTH{1'b0}};
            @(negedge clk);
            req_valid = 1'b0;

            while (!resp_valid) begin
                @(negedge clk);
            end

            observed_data = resp_rdata;
            observed_hit = resp_hit;
        end
    endtask

    task cache_write;
        input [ADDR_WIDTH-1:0] address;
        input [DATA_WIDTH-1:0] data;
        begin
            while (!req_ready) begin
                @(negedge clk);
            end

            req_valid = 1'b1;
            req_write = 1'b1;
            req_addr = address;
            req_wdata = data;
            @(negedge clk);
            req_valid = 1'b0;

            while (!resp_valid) begin
                @(negedge clk);
            end

            observed_data = resp_rdata;
            observed_hit = resp_hit;
        end
    endtask

    task require_counts;
        input [31:0] expected_access;
        input [31:0] expected_hit;
        input [31:0] expected_miss;
        begin
            if (access_count !== expected_access ||
                hit_count !== expected_hit ||
                miss_count !== expected_miss) begin
                $display("FAIL counters: access=%0d hit=%0d miss=%0d, expected %0d/%0d/%0d",
                    access_count, hit_count, miss_count,
                    expected_access, expected_hit, expected_miss);
                $finish;
            end
        end
    endtask

    task require_read;
        input [ADDR_WIDTH-1:0] address;
        input [DATA_WIDTH-1:0] expected_data;
        input expected_hit;
        begin
            cache_read(address);
            if (observed_data !== expected_data || observed_hit !== expected_hit) begin
                $display("FAIL read addr=0x%08h data=0x%08h hit=%0d, expected data=0x%08h hit=%0d",
                    address, observed_data, observed_hit, expected_data, expected_hit);
                $finish;
            end
        end
    endtask

    initial begin
        rst = 1'b0;
        req_valid = 1'b0;
        req_write = 1'b0;
        req_addr = 32'b0;
        req_wdata = 32'b0;
        observed_hit = 1'b0;
        observed_data = 32'b0;
        lfsr = 8'h5a;

        reset_cache();

        // Sequential words: one miss per four-word cache line.
        for (i = 0; i < 64; i = i + 1) begin
            cache_read(i * 4);
        end
        require_counts(32'd64, 32'd48, 32'd16);
        $display("CACHE sequential: access=%0d hit=%0d miss=%0d hit_rate=75.00%%",
            access_count, hit_count, miss_count);

        // A four-word working set fits in one line after one compulsory miss.
        reset_cache();
        for (pass_index = 0; pass_index < 8; pass_index = pass_index + 1) begin
            for (i = 0; i < 4; i = i + 1) begin
                cache_read(i * 4);
            end
        end
        require_counts(32'd32, 32'd31, 32'd1);
        $display("CACHE repeated-small-set: access=%0d hit=%0d miss=%0d hit_rate=96.88%%",
            access_count, hit_count, miss_count);

        // One word per line has no spatial reuse during the first pass.
        reset_cache();
        for (i = 0; i < 16; i = i + 1) begin
            cache_read(i * 16);
        end
        require_counts(32'd16, 32'd0, 32'd16);
        $display("CACHE stride-16B: access=%0d hit=%0d miss=%0d hit_rate=0.00%%",
            access_count, hit_count, miss_count);

        // Four passes over four lines: only four compulsory misses.
        reset_cache();
        for (pass_index = 0; pass_index < 4; pass_index = pass_index + 1) begin
            for (i = 0; i < 16; i = i + 1) begin
                cache_read(i * 4);
            end
        end
        require_counts(32'd64, 32'd60, 32'd4);
        $display("CACHE loop-working-set: access=%0d hit=%0d miss=%0d hit_rate=93.75%%",
            access_count, hit_count, miss_count);

        // Deterministic pseudo-random accesses are reported for later comparison.
        reset_cache();
        lfsr = 8'h5a;
        for (i = 0; i < 64; i = i + 1) begin
            cache_read({22'b0, lfsr, 2'b00});
            lfsr = {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
        end
        if (access_count !== 32'd64 || access_count !== hit_count + miss_count) begin
            $display("FAIL random pattern counters: access=%0d hit=%0d miss=%0d",
                access_count, hit_count, miss_count);
            $finish;
        end
        $display("CACHE deterministic-random: access=%0d hit=%0d miss=%0d",
            access_count, hit_count, miss_count);

        // Functional and LRU checks. A, B and C map to the same set.
        reset_cache();
        require_read(32'h0000_0000, 32'h1000_0000, 1'b0); // A miss
        require_read(32'h0000_0004, 32'h1000_0001, 1'b1); // Same line hit
        require_read(32'h0000_0080, 32'h1000_0020, 1'b0); // B fills way 1
        require_read(32'h0000_0000, 32'h1000_0000, 1'b1); // A becomes MRU
        require_read(32'h0000_0100, 32'h1000_0040, 1'b0); // C evicts B
        require_read(32'h0000_0000, 32'h1000_0000, 1'b1); // A survived
        require_read(32'h0000_0080, 32'h1000_0020, 1'b0); // B was evicted

        // Write hit updates both the cached word and backing memory.
        cache_write(32'h0000_0004, 32'hdead_beef);
        if (observed_hit !== 1'b1 || u_memory.mem[1] !== 32'hdead_beef) begin
            $display("FAIL write hit: hit=%0d backing=0x%08h",
                observed_hit, u_memory.mem[1]);
            $finish;
        end
        require_read(32'h0000_0004, 32'hdead_beef, 1'b1);

        // Write miss is forwarded but not allocated; the following read misses.
        cache_write(32'h0000_0180, 32'hcafe_babe);
        if (observed_hit !== 1'b0 || u_memory.mem[32'h0180 >> 2] !== 32'hcafe_babe) begin
            $display("FAIL write miss: hit=%0d backing=0x%08h",
                observed_hit, u_memory.mem[32'h0180 >> 2]);
            $finish;
        end
        require_read(32'h0000_0180, 32'hcafe_babe, 1'b0);

        require_counts(32'd11, 32'd5, 32'd6);
        if (access_count !== hit_count + miss_count) begin
            $display("FAIL invariant: access_count != hit_count + miss_count");
            $finish;
        end

        $display("PASS: two-way cache refill, LRU, write-through, no-write-allocate and statistics passed");
        $finish;
    end

    initial begin
        #1000000;
        $display("FAIL: cache test timed out");
        $finish;
    end
endmodule

module cache_memory_model #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter MEM_WORDS = 1024,
    parameter RESPONSE_DELAY = 2
)(
    input wire clk,
    input wire rst,
    input wire req_valid,
    output wire req_ready,
    input wire req_write,
    input wire [ADDR_WIDTH-1:0] req_addr,
    input wire [DATA_WIDTH-1:0] req_wdata,
    output reg resp_valid,
    output reg [DATA_WIDTH-1:0] resp_rdata
);
    reg [DATA_WIDTH-1:0] mem [0:MEM_WORDS-1];
    reg pending;
    reg pending_write;
    reg [ADDR_WIDTH-1:0] pending_addr;
    reg [DATA_WIDTH-1:0] pending_wdata;
    integer delay_count;
    integer mem_index;

    assign req_ready = !pending;

    initial begin
        for (mem_index = 0; mem_index < MEM_WORDS; mem_index = mem_index + 1) begin
            mem[mem_index] = 32'h1000_0000 + mem_index;
        end
        pending = 1'b0;
        pending_write = 1'b0;
        pending_addr = {ADDR_WIDTH{1'b0}};
        pending_wdata = {DATA_WIDTH{1'b0}};
        delay_count = 0;
        resp_valid = 1'b0;
        resp_rdata = {DATA_WIDTH{1'b0}};
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pending <= 1'b0;
            pending_write <= 1'b0;
            pending_addr <= {ADDR_WIDTH{1'b0}};
            pending_wdata <= {DATA_WIDTH{1'b0}};
            delay_count <= 0;
            resp_valid <= 1'b0;
            resp_rdata <= {DATA_WIDTH{1'b0}};
        end else begin
            resp_valid <= 1'b0;

            if (pending) begin
                if (delay_count == 0) begin
                    if (pending_write) begin
                        mem[pending_addr[ADDR_WIDTH-1:2]] <= pending_wdata;
                        resp_rdata <= {DATA_WIDTH{1'b0}};
                    end else begin
                        resp_rdata <= mem[pending_addr[ADDR_WIDTH-1:2]];
                    end
                    resp_valid <= 1'b1;
                    pending <= 1'b0;
                end else begin
                    delay_count <= delay_count - 1;
                end
            end else if (req_valid) begin
                pending <= 1'b1;
                pending_write <= req_write;
                pending_addr <= req_addr;
                pending_wdata <= req_wdata;
                delay_count <= RESPONSE_DELAY - 1;
            end
        end
    end
endmodule
