// Multi-cycle division unit (restoring algorithm, 32 iterations)
// Handles DIV / DIVU / REM / REMU
// RISC-V corner cases:
//   divide-by-zero → quotient = -1, remainder = dividend
//   signed overflow (-2^31 / -1) → quotient = -2^31, remainder = 0
module div_unit(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,           // pulse to begin
    input  wire [31:0] dividend,
    input  wire [31:0] divisor,
    input  wire [2:0]  funct3,          // 100=DIV, 101=DIVU, 110=REM, 111=REMU
    output reg  [31:0] result,
    output reg         done
);
    localparam IDLE  = 2'b00;
    localparam CALC  = 2'b01;
    localparam DONE_S = 2'b10;
    localparam SPECIAL_DONE = 2'b11;

    reg [1:0]  state;
    reg [5:0]  iter;      // 0..31
    reg [31:0] Q;         // quotient (shift register, also holds dividend init)
    reg [31:0] R;         // remainder
    reg [31:0] D;         // divisor (absolute value)
    reg        sign_q;    // quotient should be negated
    // remainder sign: same as dividend sign (RISC-V spec)

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state  <= IDLE;
            iter   <= 6'd0;
            Q      <= 32'd0;
            R      <= 32'd0;
            D      <= 32'd0;
            sign_q <= 1'b0;
            result <= 32'd0;
            done   <= 1'b0;
        end else begin
            case (state)
                // ------------------------------------------------------------
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        // --- handle corner cases in the first cycle ---
                        // divide-by-zero
                        if (divisor == 32'd0) begin
                            result <= (funct3[1]) ? dividend   // REM/REMU: rd=dividend
                                                   : 32'hffffffff; // DIV/DIVU: rd=-1
                            state <= SPECIAL_DONE;
                        end
                        // signed overflow: -2^31 / -1
                        else if (funct3 == 3'b100 && dividend == 32'h80000000 && divisor == 32'hffffffff) begin
                            result <= (funct3[1]) ? 32'd0             // REM
                                                   : 32'h80000000;    // DIV
                            state <= SPECIAL_DONE;
                        end
                        // --- normal path ---
                        else if (funct3 == 3'b100) begin          // DIV (signed)
                            sign_q <= dividend[31] ^ divisor[31];
                            Q <= dividend[31]  ? (~dividend + 32'd1) : dividend;
                            D <= divisor[31]   ? (~divisor  + 32'd1) : divisor;
                            R <= 32'd0;
                            iter <= 6'd0;
                            state <= CALC;
                        end else if (funct3 == 3'b110) begin       // REM (signed)
                            sign_q <= 1'b0;                        // remainder sign ≠ quotient sign
                            Q <= dividend[31]  ? (~dividend + 32'd1) : dividend;
                            D <= divisor[31]   ? (~divisor  + 32'd1) : divisor;
                            R <= 32'd0;
                            iter <= 6'd0;
                            state <= CALC;
                        end else begin                              // DIVU / REMU
                            sign_q <= 1'b0;
                            Q <= dividend;
                            D <= divisor;
                            R <= 32'd0;
                            iter <= 6'd0;
                            state <= CALC;
                        end
                    end
                end

                // ------------------------------------------------------------
                CALC: begin
                    // Restoring step:
                    //   {R, Q} <<= 1
                    //   R_shifted = {R[30:0], Q[31]}
                    //   Q_shifted = {Q[30:0], 1'b0}
                    {R, Q} <= {R[30:0], Q, 1'b0};  // shift left, Q[0] = 0
                    // Now R holds the shifted value; try subtract
                    if ({R[30:0], Q[31]} >= D) begin
                        R <= {R[30:0], Q[31]} - D;
                        Q[0] <= 1'b1;
                    end
                    iter <= iter + 6'd1;
                    if (iter == 6'd31) state <= DONE_S;
                end

                // ------------------------------------------------------------
                DONE_S: begin
                    done <= 1'b1;
                    // Compute final result
                    case (funct3)
                        3'b100: result <= sign_q ? (~Q + 32'd1) : Q;         // DIV
                        3'b101: result <= Q;                                   // DIVU
                        3'b110: result <= dividend[31] ? (~R + 32'd1) : R;    // REM
                        3'b111: result <= R;                                   // REMU
                        default: result <= Q;
                    endcase
                    state <= IDLE;
                end

                SPECIAL_DONE: begin
                    done <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
