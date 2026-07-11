`timescale 1ns/1ps

module data_cache #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter NUM_SETS = 8,
    parameter WORDS_PER_LINE = 4
)(
    input wire clk,
    input wire rst,

    input wire req_valid,
    output wire req_ready,
    input wire req_write,
    input wire [ADDR_WIDTH-1:0] req_addr,
    input wire [DATA_WIDTH-1:0] req_wdata,

    output reg resp_valid,
    output reg [DATA_WIDTH-1:0] resp_rdata,
    output reg resp_hit,
    output wire busy,

    output reg mem_req_valid,
    input wire mem_req_ready,
    output reg mem_req_write,
    output reg [ADDR_WIDTH-1:0] mem_req_addr,
    output reg [DATA_WIDTH-1:0] mem_req_wdata,
    input wire mem_resp_valid,
    input wire [DATA_WIDTH-1:0] mem_resp_rdata,

    output reg [31:0] access_count,
    output reg [31:0] hit_count,
    output reg [31:0] miss_count
);
    localparam BYTE_OFFSET_BITS = 2;
    localparam WORD_OFFSET_BITS = $clog2(WORDS_PER_LINE);
    localparam INDEX_BITS = $clog2(NUM_SETS);
    localparam LINE_OFFSET_BITS = BYTE_OFFSET_BITS + WORD_OFFSET_BITS;
    localparam TAG_WIDTH = ADDR_WIDTH - LINE_OFFSET_BITS - INDEX_BITS;
    localparam LINE_WORDS = NUM_SETS * WORDS_PER_LINE;

    localparam [3:0] STATE_IDLE = 4'd0;
    localparam [3:0] STATE_LOOKUP = 4'd1;
    localparam [3:0] STATE_WRITE_REQ = 4'd2;
    localparam [3:0] STATE_WRITE_WAIT = 4'd3;
    localparam [3:0] STATE_REFILL_REQ = 4'd4;
    localparam [3:0] STATE_REFILL_WAIT = 4'd5;

    reg [3:0] state;

    reg [TAG_WIDTH-1:0] tag_way0 [0:NUM_SETS-1];
    reg [TAG_WIDTH-1:0] tag_way1 [0:NUM_SETS-1];
    reg valid_way0 [0:NUM_SETS-1];
    reg valid_way1 [0:NUM_SETS-1];
    reg lru_way [0:NUM_SETS-1];
    reg [DATA_WIDTH-1:0] data_way0 [0:LINE_WORDS-1];
    reg [DATA_WIDTH-1:0] data_way1 [0:LINE_WORDS-1];

    reg req_write_reg;
    reg [ADDR_WIDTH-1:0] req_addr_reg;
    reg [DATA_WIDTH-1:0] req_wdata_reg;
    reg refill_way;
    reg [WORD_OFFSET_BITS-1:0] refill_word;
    reg write_response_hit;

    integer set_index;
    integer data_index;

    wire [WORD_OFFSET_BITS-1:0] lookup_word =
        req_addr_reg[LINE_OFFSET_BITS-1:BYTE_OFFSET_BITS];
    wire [INDEX_BITS-1:0] lookup_index =
        req_addr_reg[LINE_OFFSET_BITS+INDEX_BITS-1:LINE_OFFSET_BITS];
    wire [TAG_WIDTH-1:0] lookup_tag =
        req_addr_reg[ADDR_WIDTH-1:LINE_OFFSET_BITS+INDEX_BITS];
    wire [ADDR_WIDTH-1:0] line_base_addr =
        {req_addr_reg[ADDR_WIDTH-1:LINE_OFFSET_BITS], {LINE_OFFSET_BITS{1'b0}}};

    wire hit_way0 = valid_way0[lookup_index] &&
        (tag_way0[lookup_index] == lookup_tag);
    wire hit_way1 = valid_way1[lookup_index] &&
        (tag_way1[lookup_index] == lookup_tag);
    wire cache_hit = hit_way0 || hit_way1;

    wire selected_victim_way = !valid_way0[lookup_index] ? 1'b0 :
                               !valid_way1[lookup_index] ? 1'b1 :
                               lru_way[lookup_index];

    wire [DATA_WIDTH-1:0] hit_read_data = hit_way0 ?
        data_way0[lookup_index * WORDS_PER_LINE + lookup_word] :
        data_way1[lookup_index * WORDS_PER_LINE + lookup_word];

    assign req_ready = (state == STATE_IDLE);
    assign busy = (state != STATE_IDLE);

    always @(*) begin
        mem_req_valid = 1'b0;
        mem_req_write = 1'b0;
        mem_req_addr = {ADDR_WIDTH{1'b0}};
        mem_req_wdata = {DATA_WIDTH{1'b0}};

        case (state)
            STATE_WRITE_REQ: begin
                mem_req_valid = 1'b1;
                mem_req_write = 1'b1;
                mem_req_addr = req_addr_reg;
                mem_req_wdata = req_wdata_reg;
            end
            STATE_REFILL_REQ: begin
                mem_req_valid = 1'b1;
                mem_req_write = 1'b0;
                mem_req_addr = line_base_addr + (refill_word * 4);
            end
            default: begin
                mem_req_valid = 1'b0;
            end
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= STATE_IDLE;
            req_write_reg <= 1'b0;
            req_addr_reg <= {ADDR_WIDTH{1'b0}};
            req_wdata_reg <= {DATA_WIDTH{1'b0}};
            refill_way <= 1'b0;
            refill_word <= {WORD_OFFSET_BITS{1'b0}};
            write_response_hit <= 1'b0;
            resp_valid <= 1'b0;
            resp_rdata <= {DATA_WIDTH{1'b0}};
            resp_hit <= 1'b0;
            access_count <= 32'b0;
            hit_count <= 32'b0;
            miss_count <= 32'b0;

            for (set_index = 0; set_index < NUM_SETS; set_index = set_index + 1) begin
                tag_way0[set_index] <= {TAG_WIDTH{1'b0}};
                tag_way1[set_index] <= {TAG_WIDTH{1'b0}};
                valid_way0[set_index] <= 1'b0;
                valid_way1[set_index] <= 1'b0;
                lru_way[set_index] <= 1'b0;
            end

            for (data_index = 0; data_index < LINE_WORDS; data_index = data_index + 1) begin
                data_way0[data_index] <= {DATA_WIDTH{1'b0}};
                data_way1[data_index] <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            resp_valid <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    if (req_valid) begin
                        req_write_reg <= req_write;
                        req_addr_reg <= req_addr;
                        req_wdata_reg <= req_wdata;
                        access_count <= access_count + 32'd1;
                        state <= STATE_LOOKUP;
                    end
                end

                STATE_LOOKUP: begin
                    if (cache_hit) begin
                        hit_count <= hit_count + 32'd1;

                        if (hit_way0) begin
                            lru_way[lookup_index] <= 1'b1;
                        end else begin
                            lru_way[lookup_index] <= 1'b0;
                        end

                        if (req_write_reg) begin
                            if (hit_way0) begin
                                data_way0[lookup_index * WORDS_PER_LINE + lookup_word]
                                    <= req_wdata_reg;
                            end else begin
                                data_way1[lookup_index * WORDS_PER_LINE + lookup_word]
                                    <= req_wdata_reg;
                            end

                            write_response_hit <= 1'b1;
                            state <= STATE_WRITE_REQ;
                        end else begin
                            resp_valid <= 1'b1;
                            resp_rdata <= hit_read_data;
                            resp_hit <= 1'b1;
                            state <= STATE_IDLE;
                        end
                    end else begin
                        miss_count <= miss_count + 32'd1;

                        if (req_write_reg) begin
                            write_response_hit <= 1'b0;
                            state <= STATE_WRITE_REQ;
                        end else begin
                            refill_way <= selected_victim_way;
                            refill_word <= {WORD_OFFSET_BITS{1'b0}};
                            state <= STATE_REFILL_REQ;
                        end
                    end
                end

                STATE_WRITE_REQ: begin
                    if (mem_req_ready) begin
                        state <= STATE_WRITE_WAIT;
                    end
                end

                STATE_WRITE_WAIT: begin
                    if (mem_resp_valid) begin
                        resp_valid <= 1'b1;
                        resp_rdata <= {DATA_WIDTH{1'b0}};
                        resp_hit <= write_response_hit;
                        state <= STATE_IDLE;
                    end
                end

                STATE_REFILL_REQ: begin
                    if (mem_req_ready) begin
                        state <= STATE_REFILL_WAIT;
                    end
                end

                STATE_REFILL_WAIT: begin
                    if (mem_resp_valid) begin
                        if (refill_way == 1'b0) begin
                            data_way0[lookup_index * WORDS_PER_LINE + refill_word]
                                <= mem_resp_rdata;
                        end else begin
                            data_way1[lookup_index * WORDS_PER_LINE + refill_word]
                                <= mem_resp_rdata;
                        end

                        if (refill_word == WORDS_PER_LINE - 1) begin
                            if (refill_way == 1'b0) begin
                                tag_way0[lookup_index] <= lookup_tag;
                                valid_way0[lookup_index] <= 1'b1;
                                lru_way[lookup_index] <= 1'b1;
                            end else begin
                                tag_way1[lookup_index] <= lookup_tag;
                                valid_way1[lookup_index] <= 1'b1;
                                lru_way[lookup_index] <= 1'b0;
                            end

                            resp_valid <= 1'b1;
                            resp_hit <= 1'b0;
                            if (lookup_word == refill_word) begin
                                resp_rdata <= mem_resp_rdata;
                            end else if (refill_way == 1'b0) begin
                                resp_rdata <= data_way0[
                                    lookup_index * WORDS_PER_LINE + lookup_word];
                            end else begin
                                resp_rdata <= data_way1[
                                    lookup_index * WORDS_PER_LINE + lookup_word];
                            end
                            state <= STATE_IDLE;
                        end else begin
                            refill_word <= refill_word + {{(WORD_OFFSET_BITS-1){1'b0}}, 1'b1};
                            state <= STATE_REFILL_REQ;
                        end
                    end
                end

                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end
endmodule
