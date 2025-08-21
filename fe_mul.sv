module fe_mul (
    input  wire clk,
    input  wire reset,
    input  wire start,
    input  signed [319:0] f,
    input  signed [319:0] g,
    output reg signed [319:0] h,
    output reg done
);

    localparam [2:0] IDLE       = 3'b000,
                     MULTIPLY   = 3'b001,
                     CARRY_PROP = 3'b010,
                     FINISHED   = 3'b011;

    reg [2:0] state, next_state;
    reg [3:0] counter;
    reg [3:0] term_idx;

    // Carry state
    reg [3:0] carry_stage;      // 0..11
    reg [1:0] carry_substep;    // 0: calc, 1: add, 2: sub

    // Extract elements
    wire signed [31:0] f_elem [0:9];
    wire signed [31:0] g_elem [0:9];
    genvar i;
    generate
        for (i = 0; i < 10; i = i + 1) begin : extract_elements
            assign f_elem[i] = f[32*i+31:32*i];
            assign g_elem[i] = g[32*i+31:32*i];
        end
    endgenerate

    reg signed [63:0] h_temp [0:9];
    reg signed [63:0] carry_temp;

    // Operand selection logic
    wire signed [31:0] f_operand;
    wire signed [31:0] g_operand;
    assign f_operand = ((counter[0] == 1'b0) && (term_idx[0] == 1'b1)) ? 
                       (f_elem[term_idx] << 1) : f_elem[term_idx];
    wire [4:0] idx_diff = {1'b0, counter} - {1'b0, term_idx};
    wire use_g19 = (idx_diff[4] == 1'b1);
    wire [3:0] g_index = use_g19 ? (idx_diff[3:0] + 4'd10) : idx_diff[3:0];
    wire signed [31:0] g_base = g_elem[g_index];
    assign g_operand = use_g19 ? ((g_base << 4) + (g_base << 1) + g_base) : g_base;
    wire signed [63:0] product = f_operand * g_operand;

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

    // Carry propagation parameters
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

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            state <= IDLE;
            counter <= 0;
            term_idx <= 0;
            carry_stage <= 0;
            carry_substep <= 0;
            done <= 0;
            h <= 0;
            carry_temp <= 0;
            for (integer j = 0; j < 10; j = j + 1) begin
                h_temp[j] <= 0;
            end
        end else begin
            state <= next_state;
            case (state)
                IDLE: begin
                    done <= 0;
                    counter <= 0;
                    term_idx <= 0;
                    carry_stage <= 0;
                    carry_substep <= 0;
                    if (start) begin
                        for (integer j = 0; j < 10; j = j + 1) begin
                            h_temp[j] <= 0;
                        end
                    end
                end

                MULTIPLY: begin
                    h_temp[counter] <= h_temp[counter] + product;
                    if (term_idx == 9) begin
                        term_idx <= 0;
                        if (counter == 9) begin
                            // Multiplication complete
                        end else begin
                            counter <= counter + 1;
                        end
                    end else begin
                        term_idx <= term_idx + 1;
                    end
                end

                CARRY_PROP: begin
                    case (carry_substep)
                        0: begin // Calculate carry
                            if (shift_amt == 25)
                                carry_temp <= (h_temp[src_idx] + (1 << 24)) >>> 25;
                            else
                                carry_temp <= (h_temp[src_idx] + (1 << 25)) >>> 26;
                            carry_substep <= 1;
                        end
                        1: begin // Add carry
                            if (is_mult19)
                                h_temp[dst_idx] <= h_temp[dst_idx] + carry_temp * 19;
                            else
                                h_temp[dst_idx] <= h_temp[dst_idx] + carry_temp;
                            carry_substep <= 2;
                        end
                        2: begin // Subtract shifted carry
                            h_temp[src_idx] <= h_temp[src_idx] - SHL64(carry_temp, shift_amt);
                            if (is_final_stage) begin
                                carry_stage <= 0;
                                carry_substep <= 0;
                            end else begin
                                carry_stage <= carry_stage + 1;
                                carry_substep <= 0;
                            end
                        end
                    endcase
                end

                FINISHED: begin
                    h <= {h_temp[9][31:0], h_temp[8][31:0], h_temp[7][31:0], 
                          h_temp[6][31:0], h_temp[5][31:0], h_temp[4][31:0], 
                          h_temp[3][31:0], h_temp[2][31:0], h_temp[1][31:0], 
                          h_temp[0][31:0]};
                    done <= 1;
                end
            endcase
        end
    end

    always @(*) begin
        case (state)
            IDLE: next_state = start ? MULTIPLY : IDLE;
            MULTIPLY: next_state = (counter == 9 && term_idx == 9) ? CARRY_PROP : MULTIPLY;
            CARRY_PROP: next_state = (carry_stage == 11 && carry_substep == 2) ? FINISHED : CARRY_PROP;
            FINISHED: next_state = start ? FINISHED : IDLE;
            default: next_state = IDLE;
        endcase
    end

endmodule