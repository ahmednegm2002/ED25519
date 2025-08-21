module ge_madd(
    input clk,
    input reset,
    input start,
    output reg done,
    
    // Input port structure p (ge_p3)
    input signed [319:0] p_X,
    input signed [319:0] p_Y,
    input signed [319:0] p_Z,
    input signed [319:0] p_T,
    
    // Input port structure q (ge_cached)
    input signed [319:0] q_yplusx,
    input signed [319:0] q_yminusx,
    input signed [319:0] q_xy2d,
    
    // Output port structure r (ge_p1p1)
    output reg signed [319:0] r_X,
    output reg signed [319:0] r_Y,
    output reg signed [319:0] r_Z,
    output reg signed [319:0] r_T
);

    // State machine states
    typedef enum logic [3:0] {
        IDLE,
        CALC_YpX1_YmX1,
        CALC_A_START,
        CALC_A_WAIT,
        CALC_B_START,
        CALC_B_WAIT,
        CALC_C_START,
        CALC_C_WAIT,
        CALC_D,
        CALC_XY,
        CALC_ZT,
        DONE_STATE
    } state_t;
    
    state_t current_state, next_state;

    // Intermediate registers
    reg signed [319:0] YpX1, YmX1;
    reg signed [319:0] A, B, C, D;
    
    // Control signals for multiplexers
    reg [1:0] add_sel, sub_sel, mul_sel;
    reg mul_start;
    wire mul_done;
    
    // Arithmetic unit inputs/outputs
    reg signed [319:0] add_f, add_g, add_h;
    reg signed [319:0] sub_f, sub_g, sub_h;
    reg signed [319:0] mul_f, mul_g, mul_h;
    
    // Single instance of each arithmetic unit
    fe_add add_unit (
        .f(add_f), 
        .g(add_g), 
        .h(add_h)
    );
    
    fe_sub sub_unit (
        .f(sub_f), 
        .g(sub_g), 
        .h(sub_h)
    );
    
    // Sequential multiplier with control signals
    fe_mul mul_unit (
        .clk(clk),
        .reset(reset),
        .start(mul_start),
        .done(mul_done),
        .f(mul_f), 
        .g(mul_g), 
        .h(mul_h)
    );
    
    // Input multiplexers for add unit
    always_comb begin
        case (add_sel)
            2'b00: begin // YpX1 = p_Y + p_X
                add_f = p_Y;
                add_g = p_X;
            end
            2'b01: begin // D = p_Z + p_Z (2*p_Z)
                add_f = p_Z;
                add_g = p_Z;
            end
            2'b10: begin // r_Y = A + B
                add_f = A;
                add_g = B;
            end
            2'b11: begin // r_Z = D + C
                add_f = D;
                add_g = C;
            end
            default: begin
                add_f = 320'b0;
                add_g = 320'b0;
            end
        endcase
    end
    
    // Input multiplexers for sub unit
    always_comb begin
        case (sub_sel)
            2'b00: begin // YmX1 = p_Y - p_X
                sub_f = p_Y;
                sub_g = p_X;
            end
            2'b01: begin // r_X = A - B
                sub_f = A;
                sub_g = B;
            end
            2'b10: begin // r_T = D - C
                sub_f = D;
                sub_g = C;
            end
            default: begin
                sub_f = 320'b0;
                sub_g = 320'b0;
            end
        endcase
    end
    
    // Input multiplexers for mul unit
    always_comb begin
        case (mul_sel)
            2'b00: begin // A = YpX1 * q_yplusx
                mul_f = YpX1;
                mul_g = q_yplusx;
            end
            2'b01: begin // B = YmX1 * q_yminusx
                mul_f = YmX1;
                mul_g = q_yminusx;
            end
            2'b10: begin // C = q_xy2d * p_T
                mul_f = q_xy2d;
                mul_g = p_T;
            end
            default: begin
                mul_f = 320'b0;
                mul_g = 320'b0;
            end
        endcase
    end
    
    // State machine sequential logic
    always_ff @(posedge clk or negedge reset) begin
        if (!reset) begin
            current_state <= IDLE;
            YpX1 <= 320'b0;
            YmX1 <= 320'b0;
            A <= 320'b0;
            B <= 320'b0;
            C <= 320'b0;
            D <= 320'b0;
            r_X <= 320'b0;
            r_Y <= 320'b0;
            r_Z <= 320'b0;
            r_T <= 320'b0;
            done <= 1'b0;
        end else begin
            current_state <= next_state;
            
            // Register intermediate results based on current state
            case (current_state)
                CALC_YpX1_YmX1: begin
                    YpX1 <= add_h;  // YpX1 = p_Y + p_X
                    YmX1 <= sub_h;  // YmX1 = p_Y - p_X
                end
                CALC_A_WAIT: begin
                    if (mul_done) begin
                        A <= mul_h;    // A = YpX1 * q_yplusx
                    end
                end
                CALC_B_WAIT: begin
                    if (mul_done) begin
                        B <= mul_h;    // B = YmX1 * q_yminusx
                    end
                end
                CALC_C_WAIT: begin
                    if (mul_done) begin
                        C <= mul_h;    // C = q_xy2d * p_T
                    end
                end
                CALC_D: begin
                    D <= add_h;    // D = p_Z + p_Z (2*p_Z)
                end
                CALC_XY: begin
                    r_X <= sub_h;  // r_X = A - B
                    r_Y <= add_h;  // r_Y = A + B
                end
                CALC_ZT: begin
                    r_Z <= add_h;  // r_Z = D + C
                    r_T <= sub_h;  // r_T = D - C
                end
                DONE_STATE: begin
                    done <= 1'b1;
                end
                default: begin
                    done <= 1'b0;
                end
            endcase
        end
    end
    
    // State machine combinational logic
    always_comb begin
        next_state = current_state;
        add_sel = 2'b00;
        sub_sel = 2'b00;
        mul_sel = 2'b00;
        mul_start = 1'b0;
        
        case (current_state)
            IDLE: begin
                if (start) begin
                    next_state = CALC_YpX1_YmX1;
                end
            end
            
            CALC_YpX1_YmX1: begin
                add_sel = 2'b00; // YpX1 = p_Y + p_X
                sub_sel = 2'b00; // YmX1 = p_Y - p_X
                next_state = CALC_A_START;
            end
            
            CALC_A_START: begin
                mul_sel = 2'b00; // A = YpX1 * q_yplusx
                mul_start = 1'b1;
                next_state = CALC_A_WAIT;
            end
            
            CALC_A_WAIT: begin
                mul_sel = 2'b00; // Keep inputs stable
                if (mul_done) begin
                    next_state = CALC_B_START;
                end
            end
            
            CALC_B_START: begin
                mul_sel = 2'b01; // B = YmX1 * q_yminusx
                mul_start = 1'b1;
                next_state = CALC_B_WAIT;
            end
            
            CALC_B_WAIT: begin
                mul_sel = 2'b01; // Keep inputs stable
                if (mul_done) begin
                    next_state = CALC_C_START;
                end
            end
            
            CALC_C_START: begin
                mul_sel = 2'b10; // C = q_xy2d * p_T
                mul_start = 1'b1;
                next_state = CALC_C_WAIT;
            end
            
            CALC_C_WAIT: begin
                mul_sel = 2'b10; // Keep inputs stable
                if (mul_done) begin
                    next_state = CALC_D;
                end
            end
            
            CALC_D: begin
                add_sel = 2'b01; // D = p_Z + p_Z (2*p_Z)
                next_state = CALC_XY;
            end
            
            CALC_XY: begin
                sub_sel = 2'b01; // r_X = A - B
                add_sel = 2'b10; // r_Y = A + B
                next_state = CALC_ZT;
            end
            
            CALC_ZT: begin
                add_sel = 2'b11; // r_Z = D + C
                sub_sel = 2'b10; // r_T = D - C
                next_state = DONE_STATE;
            end
            
            DONE_STATE: begin
                if (!start) begin
                    next_state = IDLE;
                end
            end
            
            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule