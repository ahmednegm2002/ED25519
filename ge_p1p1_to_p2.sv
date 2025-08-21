module ge_p1p1_to_p2(
    input clk,
    input reset,
    input start,
    output reg done,
    
    // Input port structure p (ge_p1p1)
    input signed [319:0] p_X,
    input signed [319:0] p_Y,
    input signed [319:0] p_Z,
    input signed [319:0] p_T,
    
    // Output port structure r (ge_p2)
    output reg signed [319:0] r_X,
    output reg signed [319:0] r_Y,
    output reg signed [319:0] r_Z
);

    // State machine states
    typedef enum logic [2:0] {
        IDLE,
        CALC_X_START,
        CALC_X_WAIT,
        CALC_Y_START,
        CALC_Y_WAIT,
        CALC_Z_START,
        CALC_Z_WAIT,
        DONE_STATE
    } state_t;
    
    state_t current_state, next_state;
    
    // Control signals for multiplexer
    reg [1:0] mul_sel;
    reg mul_start;
    wire mul_done;
    
    // Multiplier unit inputs/outputs
    reg signed [319:0] mul_f, mul_g;
    wire signed [319:0] mul_h;
    
    // Single instance of multiplier unit
    fe_mul mul_unit (
        .clk(clk),
        .reset(reset),
        .start(mul_start),
        .done(mul_done),
        .f(mul_f), 
        .g(mul_g), 
        .h(mul_h)
    );
    
    // Input multiplexer for mul unit
    always_comb begin
        case (mul_sel)
            2'b00: begin // r_X = p_X * p_T
                mul_f = p_X;
                mul_g = p_T;
            end
            2'b01: begin // r_Y = p_Y * p_Z
                mul_f = p_Y;
                mul_g = p_Z;
            end
            2'b10: begin // r_Z = p_Z * p_T
                mul_f = p_Z;
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
            r_X <= 320'b0;
            r_Y <= 320'b0;
            r_Z <= 320'b0;
            done <= 1'b0;
        end else begin
            current_state <= next_state;
            
            // Register results based on current state
            case (current_state)
                CALC_X_WAIT: begin
                    if (mul_done) begin
                        r_X <= mul_h;    // r_X = p_X * p_T
                    end
                end
                CALC_Y_WAIT: begin
                    if (mul_done) begin
                        r_Y <= mul_h;    // r_Y = p_Y * p_Z
                    end
                end
                CALC_Z_WAIT: begin
                    if (mul_done) begin
                        r_Z <= mul_h;    // r_Z = p_Z * p_T
                    end
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
        mul_sel = 2'b00;
        mul_start = 1'b0;
        
        case (current_state)
            IDLE: begin
                if (start) begin
                    next_state = CALC_X_START;
                end
            end
            
            CALC_X_START: begin
                mul_sel = 2'b00; // r_X = p_X * p_T
                mul_start = 1'b1;
                next_state = CALC_X_WAIT;
            end
            
            CALC_X_WAIT: begin
                mul_sel = 2'b00; // Keep inputs stable
                if (mul_done) begin
                    next_state = CALC_Y_START;
                end
            end
            
            CALC_Y_START: begin
                mul_sel = 2'b01; // r_Y = p_Y * p_Z
                mul_start = 1'b1;
                next_state = CALC_Y_WAIT;
            end
            
            CALC_Y_WAIT: begin
                mul_sel = 2'b01; // Keep inputs stable
                if (mul_done) begin
                    next_state = CALC_Z_START;
                end
            end
            
            CALC_Z_START: begin
                mul_sel = 2'b10; // r_Z = p_Z * p_T
                mul_start = 1'b1;
                next_state = CALC_Z_WAIT;
            end
            
            CALC_Z_WAIT: begin
                mul_sel = 2'b10; // Keep inputs stable
                if (mul_done) begin
                    next_state = DONE_STATE;
                end
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