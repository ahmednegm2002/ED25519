module fe_sq (
    input  wire clk,
    input  wire reset,
    input  wire start,
    input  signed [319:0] f,
    output reg signed [319:0] h,
    output reg done
);

    // State machine states
    localparam [2:0] 
        IDLE       = 3'b000,
        PRECOMPUTE = 3'b001,
        MULT_ACC   = 3'b010,
        CARRY_PROP = 3'b011,
        FINISH     = 3'b100;

    reg [2:0] state;
    reg [3:0] precomp_count;  // 0-12 (13 cycles)
    reg [7:0] mult_acc_count; // 0-109 (110 cycles)
    reg [3:0] target_H_index_reg; // Registered target index

    // Carry state (similar to fe_mul)
    reg [3:0] carry_stage;      // 0..11
    reg [1:0] carry_substep;    // 0: calc, 1: add, 2: sub

    // Latch input field element
    reg signed [319:0] f_reg;
    wire signed [31:0] f0 = f_reg[31:0];
    wire signed [31:0] f1 = f_reg[63:32];
    wire signed [31:0] f2 = f_reg[95:64];
    wire signed [31:0] f3 = f_reg[127:96];
    wire signed [31:0] f4 = f_reg[159:128];
    wire signed [31:0] f5 = f_reg[191:160];
    wire signed [31:0] f6 = f_reg[223:192];
    wire signed [31:0] f7 = f_reg[255:224];
    wire signed [31:0] f8 = f_reg[287:256];
    wire signed [31:0] f9 = f_reg[319:288];

    // Precomputed terms
    reg signed [31:0] f0_2, f1_2, f2_2, f3_2, f4_2, f5_2, f6_2, f7_2;
    reg signed [31:0] f5_38, f6_19, f7_38, f8_19, f9_38;
    reg signed [63:0] carry_temp;
    
    // Accumulator array
    reg signed [63:0] H [0:9];
    reg signed [63:0] mul_product_reg;
    reg signed [31:0] mul_a, mul_b;
    reg [3:0] next_target_H_index;

    // Multiplier (combinational)
    wire signed [63:0] mul_product = mul_a * mul_b;

    // SHL64 function for compatibility
    function signed [63:0] SHL64;
        input signed [63:0] s;
        input [5:0] lshift;
        reg [63:0] unsigned_s;
        begin
            unsigned_s = s;
            SHL64 = (unsigned_s << lshift);
        end
    endfunction

    // Carry propagation parameters (same pattern as fe_mul)
    reg [3:0] src_idx, dst_idx;
    reg [5:0] shift_amt;
    reg       is_final_stage;
    reg       is_mult19;

    always @(*) begin
        // Default values
        src_idx = 0;
        dst_idx = 0;
        shift_amt = 0;
        is_final_stage = 0;
        is_mult19 = 0;
        case (carry_stage)
            0:  begin src_idx = 0; dst_idx = 1; shift_amt = 26; is_mult19 = 0; end
            1:  begin src_idx = 4; dst_idx = 5; shift_amt = 26; is_mult19 = 0; end
            2:  begin src_idx = 1; dst_idx = 2; shift_amt = 25; is_mult19 = 0; end
            3:  begin src_idx = 5; dst_idx = 6; shift_amt = 25; is_mult19 = 0; end
            4:  begin src_idx = 2; dst_idx = 3; shift_amt = 26; is_mult19 = 0; end
            5:  begin src_idx = 6; dst_idx = 7; shift_amt = 26; is_mult19 = 0; end
            6:  begin src_idx = 3; dst_idx = 4; shift_amt = 25; is_mult19 = 0; end
            7:  begin src_idx = 7; dst_idx = 8; shift_amt = 25; is_mult19 = 0; end
            8:  begin src_idx = 4; dst_idx = 5; shift_amt = 26; is_mult19 = 0; end
            9:  begin src_idx = 8; dst_idx = 9; shift_amt = 26; is_mult19 = 0; end
            10: begin src_idx = 9; dst_idx = 0; shift_amt = 25; is_mult19 = 1; end
            11: begin src_idx = 0; dst_idx = 1; shift_amt = 26; is_mult19 = 0; is_final_stage = 1; end
        endcase
    end

    // State machine and main computation
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            state <= IDLE;
            done <= 0;
            precomp_count <= 0;
            mult_acc_count <= 0;
            carry_stage <= 0;
            carry_substep <= 0;
            H[0] <= 0; H[1] <= 0; H[2] <= 0; H[3] <= 0; H[4] <= 0;
            H[5] <= 0; H[6] <= 0; H[7] <= 0; H[8] <= 0; H[9] <= 0;
            f_reg <= 0;
            target_H_index_reg <= 0;
            carry_temp <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        f_reg <= f;
                        state <= PRECOMPUTE;
                        precomp_count <= 0;
                        carry_stage <= 0;
                        carry_substep <= 0;
                        H[0] <= 0; H[1] <= 0; H[2] <= 0; H[3] <= 0; H[4] <= 0;
                        H[5] <= 0; H[6] <= 0; H[7] <= 0; H[8] <= 0; H[9] <= 0;
                    end
                end

                PRECOMPUTE: begin
                    case (precomp_count)
                        0: f0_2 <= mul_product;
                        1: f1_2 <= mul_product;
                        2: f2_2 <= mul_product;
                        3: f3_2 <= mul_product;
                        4: f4_2 <= mul_product;
                        5: f5_2 <= mul_product;
                        6: f6_2 <= mul_product;
                        7: f7_2 <= mul_product;
                        8: f5_38 <= mul_product;
                        9: f6_19 <= mul_product;
                        10: f7_38 <= mul_product;
                        11: f8_19 <= mul_product;
                        12: f9_38 <= mul_product;
                    endcase
                    precomp_count <= precomp_count + 1;
                    if (precomp_count == 12) begin
                        state <= MULT_ACC;
                        mult_acc_count <= 0;
                    end
                end

                MULT_ACC: begin
                    mul_product_reg <= mul_product;
                    if (!mult_acc_count[0]) begin
                        target_H_index_reg <= next_target_H_index;
                    end
                    if (mult_acc_count[0]) begin
                        H[target_H_index_reg] <= H[target_H_index_reg] + mul_product_reg;
                    end
                    mult_acc_count <= mult_acc_count + 1;
                    if (mult_acc_count == 8'd109) begin
                        state <= CARRY_PROP;
                        carry_stage <= 0;
                        carry_substep <= 0;
                    end
                end

                CARRY_PROP: begin
                    case (carry_substep)
                        0: begin // Calculate carry
                            if (shift_amt == 25)
                                carry_temp <= (H[src_idx] + (1 << 24)) >>> 25;
                            else
                                carry_temp <= (H[src_idx] + (1 << 25)) >>> 26;
                            carry_substep <= 1;
                        end
                        1: begin // Add carry
                            if (is_mult19)
                                H[dst_idx] <= H[dst_idx] + carry_temp * 19;
                            else
                                H[dst_idx] <= H[dst_idx] + carry_temp;
                            carry_substep <= 2;
                        end
                        2: begin // Subtract shifted carry
                            H[src_idx] <= H[src_idx] - SHL64(carry_temp, shift_amt);
                            if (is_final_stage) begin
                                carry_stage <= 0;
                                carry_substep <= 0;
                                state <= FINISH;
                            end else begin
                                carry_stage <= carry_stage + 1;
                                carry_substep <= 0;
                            end
                        end
                    endcase
                end

                FINISH: begin
                    h <= {H[9][31:0], H[8][31:0], H[7][31:0], H[6][31:0], H[5][31:0],
                          H[4][31:0], H[3][31:0], H[2][31:0], H[1][31:0], H[0][31:0]};
                    done <= 1;
                    if (~start) state <= IDLE;
                end
            endcase
        end
    end

    // Multiplier input selection and target index
    always @(*) begin
        mul_a = 0;
        mul_b = 0;
        next_target_H_index = 0;
        case (state)
            PRECOMPUTE: begin
                case (precomp_count)
                    0: begin mul_a = 2;     mul_b = f0; end
                    1: begin mul_a = 2;     mul_b = f1; end
                    2: begin mul_a = 2;     mul_b = f2; end
                    3: begin mul_a = 2;     mul_b = f3; end
                    4: begin mul_a = 2;     mul_b = f4; end
                    5: begin mul_a = 2;     mul_b = f5; end
                    6: begin mul_a = 2;     mul_b = f6; end
                    7: begin mul_a = 2;     mul_b = f7; end
                    8: begin mul_a = 38;    mul_b = f5; end
                    9: begin mul_a = 19;    mul_b = f6; end
                    10: begin mul_a = 38;   mul_b = f7; end
                    11: begin mul_a = 19;   mul_b = f8; end
                    12: begin mul_a = 38;   mul_b = f9; end
                endcase
            end
            MULT_ACC: begin
                if (!mult_acc_count[0]) begin
                    case (mult_acc_count[7:1])
                        0: begin mul_a = f0;      mul_b = f0;      next_target_H_index = 0; end
                        1: begin mul_a = f1_2;    mul_b = f9_38;   next_target_H_index = 0; end
                        2: begin mul_a = f2_2;    mul_b = f8_19;   next_target_H_index = 0; end
                        3: begin mul_a = f3_2;    mul_b = f7_38;   next_target_H_index = 0; end
                        4: begin mul_a = f4_2;    mul_b = f6_19;   next_target_H_index = 0; end
                        5: begin mul_a = f5;      mul_b = f5_38;   next_target_H_index = 0; end
                        6: begin mul_a = f0_2;    mul_b = f1;      next_target_H_index = 1; end
                        7: begin mul_a = f2;      mul_b = f9_38;   next_target_H_index = 1; end
                        8: begin mul_a = f3_2;    mul_b = f8_19;   next_target_H_index = 1; end
                        9: begin mul_a = f4;      mul_b = f7_38;   next_target_H_index = 1; end
                        10: begin mul_a = f5_2;   mul_b = f6_19;   next_target_H_index = 1; end
                        11: begin mul_a = f0_2;   mul_b = f2;      next_target_H_index = 2; end
                        12: begin mul_a = f1_2;   mul_b = f1;      next_target_H_index = 2; end
                        13: begin mul_a = f3_2;   mul_b = f9_38;   next_target_H_index = 2; end
                        14: begin mul_a = f4_2;   mul_b = f8_19;   next_target_H_index = 2; end
                        15: begin mul_a = f5_2;   mul_b = f7_38;   next_target_H_index = 2; end
                        16: begin mul_a = f6;     mul_b = f6_19;   next_target_H_index = 2; end
                        17: begin mul_a = f0_2;   mul_b = f3;      next_target_H_index = 3; end
                        18: begin mul_a = f1_2;   mul_b = f2;      next_target_H_index = 3; end
                        19: begin mul_a = f4;     mul_b = f9_38;   next_target_H_index = 3; end
                        20: begin mul_a = f5_2;   mul_b = f8_19;   next_target_H_index = 3; end
                        21: begin mul_a = f6;     mul_b = f7_38;   next_target_H_index = 3; end
                        22: begin mul_a = f0_2;   mul_b = f4;      next_target_H_index = 4; end
                        23: begin mul_a = f1_2;   mul_b = f3_2;    next_target_H_index = 4; end
                        24: begin mul_a = f2;     mul_b = f2;      next_target_H_index = 4; end
                        25: begin mul_a = f5_2;   mul_b = f9_38;   next_target_H_index = 4; end
                        26: begin mul_a = f6_2;   mul_b = f8_19;   next_target_H_index = 4; end
                        27: begin mul_a = f7;     mul_b = f7_38;   next_target_H_index = 4; end
                        28: begin mul_a = f0_2;   mul_b = f5;      next_target_H_index = 5; end
                        29: begin mul_a = f1_2;   mul_b = f4;      next_target_H_index = 5; end
                        30: begin mul_a = f2_2;   mul_b = f3;      next_target_H_index = 5; end
                        31: begin mul_a = f6;     mul_b = f9_38;   next_target_H_index = 5; end
                        32: begin mul_a = f7_2;   mul_b = f8_19;   next_target_H_index = 5; end
                        33: begin mul_a = f0_2;   mul_b = f6;      next_target_H_index = 6; end
                        34: begin mul_a = f1_2;   mul_b = f5_2;    next_target_H_index = 6; end
                        35: begin mul_a = f2_2;   mul_b = f4;      next_target_H_index = 6; end
                        36: begin mul_a = f3_2;   mul_b = f3;      next_target_H_index = 6; end
                        37: begin mul_a = f7_2;   mul_b = f9_38;   next_target_H_index = 6; end
                        38: begin mul_a = f8;     mul_b = f8_19;   next_target_H_index = 6; end
                        39: begin mul_a = f0_2;   mul_b = f7;      next_target_H_index = 7; end
                        40: begin mul_a = f1_2;   mul_b = f6;      next_target_H_index = 7; end
                        41: begin mul_a = f2_2;   mul_b = f5;      next_target_H_index = 7; end
                        42: begin mul_a = f3_2;   mul_b = f4;      next_target_H_index = 7; end
                        43: begin mul_a = f8;     mul_b = f9_38;   next_target_H_index = 7; end
                        44: begin mul_a = f0_2;   mul_b = f8;      next_target_H_index = 8; end
                        45: begin mul_a = f1_2;   mul_b = f7_2;    next_target_H_index = 8; end
                        46: begin mul_a = f2_2;   mul_b = f6;      next_target_H_index = 8; end
                        47: begin mul_a = f3_2;   mul_b = f5_2;    next_target_H_index = 8; end
                        48: begin mul_a = f4;     mul_b = f4;      next_target_H_index = 8; end
                        49: begin mul_a = f9;     mul_b = f9_38;   next_target_H_index = 8; end
                        50: begin mul_a = f0_2;   mul_b = f9;      next_target_H_index = 9; end
                        51: begin mul_a = f1_2;   mul_b = f8;      next_target_H_index = 9; end
                        52: begin mul_a = f2_2;   mul_b = f7;      next_target_H_index = 9; end
                        53: begin mul_a = f3_2;   mul_b = f6;      next_target_H_index = 9; end
                        54: begin mul_a = f4_2;   mul_b = f5;      next_target_H_index = 9; end
                    endcase
                end
            end
            endcase
        end

endmodule