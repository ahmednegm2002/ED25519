module ge_scalarmult_base(
    input logic clk,
    input logic reset,
    input logic start,          // Start signal to begin computation
    input logic [255:0] a,      // 256-bit scalar input (a), equivalent to unsigned char a[32]
    output logic signed [319:0] h_X,   // Output X coordinate p3
    output logic signed [319:0] h_Y,   // Output Y coordinate p3
    output logic signed [319:0] h_Z,   // Output Z coordinate p3
    output logic signed [319:0] h_T,   // Output T coordinate p3
    output logic done           // Done signal to indicate completion
);
    // Internal signal declarations
    logic signed [7:0] e [0:63];         // Exponent array, 64 elements, each 8-bits  
    logic signed [511:0] e_packed;       // Packed version of e for the carry_prop module
    logic signed [511:0] e_prop_result;  // Result from carry_prop
    logic signed [7:0] e_decomp [0:63];  // Output from decompose module
    
    // Intermediate results for each module
    logic signed [319:0] madd_r_X, madd_r_Y, madd_r_Z, madd_r_T;       // Outputs from ge_madd
    logic signed [319:0] p3_dbl_r_X, p3_dbl_r_Y, p3_dbl_r_Z, p3_dbl_r_T; // Outputs from ge_p3_dbl
    logic signed [319:0] p2_dbl_r_X, p2_dbl_r_Y, p2_dbl_r_Z, p2_dbl_r_T; // Outputs from ge_p2_dbl
    logic signed [319:0] p3_X_next, p3_Y_next, p3_Z_next, p3_T_next;  // Next p3 point values
    logic signed [319:0] p2_X_next, p2_Y_next, p2_Z_next;  // Next p2 point values
    
    // Temporary p2 point
    logic signed [319:0] s_X, s_Y, s_Z, s_T;    // Temporary p2 point
    
    // Precomputed point
    logic signed [319:0] t_yplusx, t_yminusx, t_xy2d;
    
    // Output registers
    logic signed [319:0] h_X_reg, h_Y_reg, h_Z_reg, h_T_reg;
    
    // Counter and control
    logic [6:0] i;  // Loop counter
    logic done_reg;

    // Module control signals - now start/done instead of enable
    logic select_start;          // Start signal for select module
    logic ge_madd_start;         // Start signal for ge_madd module
    logic p1p1_to_p3_start;      // Start signal for p1p1_to_p3 module
    logic p3_dbl_start;          // Start signal for ge_p3_dbl module
    logic p1p1_to_p2_start;      // Start signal for p1p1_to_p2 module
    logic p2_dbl_start;          // Start signal for ge_p2_dbl module
    
    // Module done signals
    logic ge_madd_done;
    logic p1p1_to_p3_done;
    logic p3_dbl_done;
    logic p1p1_to_p2_done;
    logic p2_dbl_done;

    // FSM state declarations
    typedef enum logic [5:0] {
        IDLE,               // Waiting for start
        DECOMPOSE,          // Decompose scalar a into e
        PACK_E,             // Pack e array into e_packed for carry_prop
        CARRY_PROP,         // Carry propagation
        UNPACK_E,           // Unpack e_prop_result into e array
        INIT_P3_0,          // Initialize h to neutral point
        INIT_ODD_LOOP,      // Initialize odd indices loop
        SELECT_ODD,         // Select for odd index
        MADD_ODD,           // ge_madd for odd index
        WAIT_MADD_ODD,      // Wait for ge_madd completion
        TO_P3_ODD,          // Convert to p3 after odd operation
        WAIT_P3_ODD,        // Wait for p1p1_to_p3 completion
        NEXT_ODD,           // Move to next odd index
        INIT_DBL,           // Initialize doubling sequence
        DBL1,               // First doubling
        WAIT_DBL1,          // Wait for first doubling completion
        TO_P2_1,            // Convert to p2 after first doubling
        WAIT_P2_1,          // Wait for p1p1_to_p2 completion
        DBL2,               // Second doubling
        WAIT_DBL2,          // Wait for second doubling completion
        TO_P2_2,            // Convert to p2 after second doubling
        WAIT_P2_2,          // Wait for p1p1_to_p2 completion
        DBL3,               // Third doubling
        WAIT_DBL3,          // Wait for third doubling completion
        TO_P2_3,            // Convert to p2 after third doubling
        WAIT_P2_3,          // Wait for p1p1_to_p2 completion
        DBL4,               // Fourth doubling
        WAIT_DBL4,          // Wait for fourth doubling completion
        TO_P3_DBL,          // Convert to p3 after fourth doubling
        WAIT_P3_DBL,        // Wait for p1p1_to_p3 completion
        INIT_EVEN_LOOP,     // Initialize even indices loop
        SELECT_EVEN,        // Select for even index
        MADD_EVEN,          // ge_madd for even index
        WAIT_MADD_EVEN,     // Wait for ge_madd completion
        TO_P3_EVEN,         // Convert to p3 after even operation
        WAIT_P3_EVEN,       // Wait for p1p1_to_p3 completion
        NEXT_EVEN,          // Move to next even index
        DONE                // Operation complete
    } state_t;
    
    state_t state, next_state;

    // Instantiate submodules
    decompose decomp_inst (
        .a(a),
        .e(e_decomp)
    );

    carry_prop carry_inst (
        .e_in(e_packed),
        .e_out(e_prop_result)
    );

    wire [4:0] pos;
    assign pos = i / 2;

    select select_inst (
        .pos(pos),
        .b(e[i]),
        .t_yplusx(t_yplusx),
        .t_yminusx(t_yminusx),
        .t_xy2d(t_xy2d)
    );
    
    // Updated ge_madd instantiation with sequential interface
    ge_madd ge_madd_inst (
        .clk(clk),
        .reset(reset),
        .start(ge_madd_start),
        .p_X(h_X_reg), .p_Y(h_Y_reg), .p_Z(h_Z_reg), .p_T(h_T_reg),
        .q_yplusx(t_yplusx), .q_yminusx(t_yminusx), .q_xy2d(t_xy2d),
        .r_X(madd_r_X), .r_Y(madd_r_Y), .r_Z(madd_r_Z), .r_T(madd_r_T),
        .done(ge_madd_done)
    );

    // Need intermediate registers to hold r values for p1p1_to_p3 input
    logic signed [319:0] r_X_reg, r_Y_reg, r_Z_reg, r_T_reg;
    
    ge_p1p1_to_p3 ge_p1p1_to_p3_inst (
        .clk(clk),
        .reset(reset),
        .start(p1p1_to_p3_start),
        .p_X(r_X_reg), .p_Y(r_Y_reg), .p_Z(r_Z_reg), .p_T(r_T_reg),
        .r_X(p3_X_next), .r_Y(p3_Y_next), .r_Z(p3_Z_next), .r_T(p3_T_next),
        .done(p1p1_to_p3_done)
    );
    
    ge_p3_dbl ge_p3_dbl_inst (
        .clk(clk),
        .reset(reset),
        .start(p3_dbl_start),
        .p_X(h_X_reg), .p_Y(h_Y_reg), .p_Z(h_Z_reg), .p_T(h_T_reg),
        .r_X(p3_dbl_r_X), .r_Y(p3_dbl_r_Y), .r_Z(p3_dbl_r_Z), .r_T(p3_dbl_r_T),
        .done(p3_dbl_done)
    );
    
    ge_p1p1_to_p2 ge_p1p1_to_p2_inst (
        .clk(clk),
        .reset(reset),
        .start(p1p1_to_p2_start),
        .p_X(r_X_reg), .p_Y(r_Y_reg), .p_Z(r_Z_reg), .p_T(r_T_reg),
        .r_X(p2_X_next), .r_Y(p2_Y_next), .r_Z(p2_Z_next),
        .done(p1p1_to_p2_done)
    );
    
    ge_p2_dbl ge_p2_dbl_inst (
        .clk(clk),
        .reset(reset),
        .start(p2_dbl_start),
        .p_X(s_X), .p_Y(s_Y), .p_Z(s_Z),
        .r_X(p2_dbl_r_X), .r_Y(p2_dbl_r_Y), .r_Z(p2_dbl_r_Z), .r_T(p2_dbl_r_T),
        .done(p2_dbl_done)
    );

    // FSM state register
    always_ff @(posedge clk or negedge reset) begin
        if (!reset) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    // Next state logic with sequential module handling
    always_comb begin
        // Default values for all start signals
        ge_madd_start = 1'b0;
        p1p1_to_p3_start = 1'b0;
        p3_dbl_start = 1'b0;
        p1p1_to_p2_start = 1'b0;
        p2_dbl_start = 1'b0;
        
        case (state)
            IDLE:           next_state = start ? DECOMPOSE : IDLE;
            DECOMPOSE:      next_state = PACK_E;
            PACK_E:         next_state = CARRY_PROP;
            CARRY_PROP:     next_state = UNPACK_E;
            UNPACK_E:       next_state = INIT_P3_0;
            INIT_P3_0:      next_state = INIT_ODD_LOOP;
            INIT_ODD_LOOP:  next_state = SELECT_ODD;
            SELECT_ODD:     next_state = MADD_ODD;
            MADD_ODD:       begin
                ge_madd_start = 1'b1;
                next_state = WAIT_MADD_ODD;
            end
            WAIT_MADD_ODD:  next_state = ge_madd_done ? TO_P3_ODD : WAIT_MADD_ODD;
            TO_P3_ODD:      begin
                p1p1_to_p3_start = 1'b1;
                next_state = WAIT_P3_ODD;
            end
            WAIT_P3_ODD:    next_state = p1p1_to_p3_done ? NEXT_ODD : WAIT_P3_ODD;
            NEXT_ODD:       begin
                if (i >= 63) next_state = INIT_DBL;
                else next_state = SELECT_ODD;
            end
            INIT_DBL:       next_state = DBL1;
            DBL1:           begin
                p3_dbl_start = 1'b1;
                next_state = WAIT_DBL1;
            end
            WAIT_DBL1:      next_state = p3_dbl_done ? TO_P2_1 : WAIT_DBL1;
            TO_P2_1:        begin
                p1p1_to_p2_start = 1'b1;
                next_state = WAIT_P2_1;
            end
            WAIT_P2_1:      next_state = p1p1_to_p2_done ? DBL2 : WAIT_P2_1;
            DBL2:           begin
                p2_dbl_start = 1'b1;
                next_state = WAIT_DBL2;
            end
            WAIT_DBL2:      next_state = p2_dbl_done ? TO_P2_2 : WAIT_DBL2;
            TO_P2_2:        begin
                p1p1_to_p2_start = 1'b1;
                next_state = WAIT_P2_2;
            end
            WAIT_P2_2:      next_state = p1p1_to_p2_done ? DBL3 : WAIT_P2_2;
            DBL3:           begin
                p2_dbl_start = 1'b1;
                next_state = WAIT_DBL3;
            end
            WAIT_DBL3:      next_state = p2_dbl_done ? TO_P2_3 : WAIT_DBL3;
            TO_P2_3:        begin
                p1p1_to_p2_start = 1'b1;
                next_state = WAIT_P2_3;
            end
            WAIT_P2_3:      next_state = p1p1_to_p2_done ? DBL4 : WAIT_P2_3;
            DBL4:           begin
                p2_dbl_start = 1'b1;
                next_state = WAIT_DBL4;
            end
            WAIT_DBL4:      next_state = p2_dbl_done ? TO_P3_DBL : WAIT_DBL4;
            TO_P3_DBL:      begin
                p1p1_to_p3_start = 1'b1;
                next_state = WAIT_P3_DBL;
            end
            WAIT_P3_DBL:    next_state = p1p1_to_p3_done ? INIT_EVEN_LOOP : WAIT_P3_DBL;
            INIT_EVEN_LOOP: next_state = SELECT_EVEN;
            SELECT_EVEN:    next_state = MADD_EVEN;
            MADD_EVEN:      begin
                ge_madd_start = 1'b1;
                next_state = WAIT_MADD_EVEN;
            end
            WAIT_MADD_EVEN: next_state = ge_madd_done ? TO_P3_EVEN : WAIT_MADD_EVEN;
            TO_P3_EVEN:     begin
                p1p1_to_p3_start = 1'b1;
                next_state = WAIT_P3_EVEN;
            end
            WAIT_P3_EVEN:   next_state = p1p1_to_p3_done ? NEXT_EVEN : WAIT_P3_EVEN;
            NEXT_EVEN:      begin
                if (i >= 62) next_state = DONE;
                else next_state = SELECT_EVEN;
            end
            DONE:           next_state = IDLE;
            default:        next_state = IDLE;
        endcase
    end

    // Main sequential logic
    always_ff @(posedge clk or negedge reset) begin
        if (!reset) begin
            i <= 0;
            done_reg <= 0;
            h_X_reg <= 0;
            h_Y_reg <= 0;
            h_Z_reg <= 0;
            h_T_reg <= 0;
            e_packed <= 0;
            s_X <= 0;
            s_Y <= 0;
            s_Z <= 0;
            s_T <= 0;
            r_X_reg <= 0;
            r_Y_reg <= 0;
            r_Z_reg <= 0;
            r_T_reg <= 0;
 
            for (int j = 0; j < 64; j++) begin
                e[j] <= 0;
            end

        end else begin
            case (state)
                IDLE: begin
                    done_reg <= 0;
                    if (start) begin
                        i <= 0;
                    end
                end
                
                DECOMPOSE: begin
                    for (int j = 0; j < 64; j++) begin
                        e[j] <= e_decomp[j];
                    end
                end
                
                PACK_E: begin
                    for (int j = 0; j < 64; j++) begin
                        e_packed[511 - 8*j -: 8] <= e[j];
                    end
                end
                
                CARRY_PROP: begin
                    // Result in e_prop_result
                end
                
                UNPACK_E: begin
                    for (int j = 0; j < 64; j++) begin
                        e[j] <= e_prop_result[511 - 8*j -: 8];
                    end
                end
                
                INIT_P3_0: begin
                    h_X_reg <= 320'h0;
                    h_Y_reg <= 320'h1;
                    h_Z_reg <= 320'h1;
                    h_T_reg <= 320'h0;
                end
                
                INIT_ODD_LOOP: begin
                    i <= 1;
                end
                
                SELECT_ODD: begin
                    // Selection happens in select_inst
                end
                
                MADD_ODD: begin
                    // ge_madd start signal asserted in combinational logic
                end
                
                WAIT_MADD_ODD: begin
                    if (ge_madd_done) begin
                        r_X_reg <= madd_r_X;
                        r_Y_reg <= madd_r_Y;
                        r_Z_reg <= madd_r_Z;
                        r_T_reg <= madd_r_T;
                    end
                end
                
                TO_P3_ODD: begin
                    // p1p1_to_p3 start signal asserted in combinational logic
                end
                
                WAIT_P3_ODD: begin
                    if (p1p1_to_p3_done) begin
                        h_X_reg <= p3_X_next;
                        h_Y_reg <= p3_Y_next;
                        h_Z_reg <= p3_Z_next;
                        h_T_reg <= p3_T_next;
                    end
                end
                
                NEXT_ODD: begin
                    if (i < 63) begin
                        i <= i + 2;
                    end
                end
                
                INIT_DBL: begin
                    // No action needed
                end
                
                DBL1: begin
                    // p3_dbl start signal asserted in combinational logic
                end
                
                WAIT_DBL1: begin
                    if (p3_dbl_done) begin
                        r_X_reg <= p3_dbl_r_X;
                        r_Y_reg <= p3_dbl_r_Y;
                        r_Z_reg <= p3_dbl_r_Z;
                        r_T_reg <= p3_dbl_r_T;
                    end
                end
                
                TO_P2_1: begin
                    // p1p1_to_p2 start signal asserted in combinational logic
                end
                
                WAIT_P2_1: begin
                    if (p1p1_to_p2_done) begin
                        s_X <= p2_X_next;
                        s_Y <= p2_Y_next;
                        s_Z <= p2_Z_next;
                    end
                end
                
                DBL2: begin
                    // p2_dbl start signal asserted in combinational logic
                end
                
                WAIT_DBL2: begin
                    if (p2_dbl_done) begin
                        r_X_reg <= p2_dbl_r_X;
                        r_Y_reg <= p2_dbl_r_Y;
                        r_Z_reg <= p2_dbl_r_Z;
                        r_T_reg <= p2_dbl_r_T;
                    end
                end
                
                TO_P2_2: begin
                    // p1p1_to_p2 start signal asserted in combinational logic
                end
                
                WAIT_P2_2: begin
                    if (p1p1_to_p2_done) begin
                        s_X <= p2_X_next;
                        s_Y <= p2_Y_next;
                        s_Z <= p2_Z_next;
                    end
                end
                
                DBL3: begin
                    // p2_dbl start signal asserted in combinational logic
                end
                
                WAIT_DBL3: begin
                    if (p2_dbl_done) begin
                        r_X_reg <= p2_dbl_r_X;
                        r_Y_reg <= p2_dbl_r_Y;
                        r_Z_reg <= p2_dbl_r_Z;
                        r_T_reg <= p2_dbl_r_T;
                    end
                end
                
                TO_P2_3: begin
                    // p1p1_to_p2 start signal asserted in combinational logic
                end
                
                WAIT_P2_3: begin
                    if (p1p1_to_p2_done) begin
                        s_X <= p2_X_next;
                        s_Y <= p2_Y_next;
                        s_Z <= p2_Z_next;
                    end
                end
                
                DBL4: begin
                    // p2_dbl start signal asserted in combinational logic
                end
                
                WAIT_DBL4: begin
                    if (p2_dbl_done) begin
                        r_X_reg <= p2_dbl_r_X;
                        r_Y_reg <= p2_dbl_r_Y;
                        r_Z_reg <= p2_dbl_r_Z;
                        r_T_reg <= p2_dbl_r_T;
                    end
                end
                
                TO_P3_DBL: begin
                    // p1p1_to_p3 start signal asserted in combinational logic
                end
                
                WAIT_P3_DBL: begin
                    if (p1p1_to_p3_done) begin
                        h_X_reg <= p3_X_next;
                        h_Y_reg <= p3_Y_next;
                        h_Z_reg <= p3_Z_next;
                        h_T_reg <= p3_T_next;
                    end
                end
                
                INIT_EVEN_LOOP: begin
                    i <= 0;
                end
                
                SELECT_EVEN: begin
                    // Selection happens in select_inst
                end
                
                MADD_EVEN: begin
                    // ge_madd start signal asserted in combinational logic
                end
                
                WAIT_MADD_EVEN: begin
                    if (ge_madd_done) begin
                        r_X_reg <= madd_r_X;
                        r_Y_reg <= madd_r_Y;
                        r_Z_reg <= madd_r_Z;
                        r_T_reg <= madd_r_T;
                    end
                end
                
                TO_P3_EVEN: begin
                    // p1p1_to_p3 start signal asserted in combinational logic
                end
                
                WAIT_P3_EVEN: begin
                    if (p1p1_to_p3_done) begin
                        h_X_reg <= p3_X_next;
                        h_Y_reg <= p3_Y_next;
                        h_Z_reg <= p3_Z_next;
                        h_T_reg <= p3_T_next;
                    end
                end
                
                NEXT_EVEN: begin
                    if (i < 62) begin
                        i <= i + 2;
                    end
                end
                
                DONE: begin
                    done_reg <= 1;
                end
            endcase
        end
    end

    // Output assignments
    assign h_X = h_X_reg;
    assign h_Y = h_Y_reg;
    assign h_Z = h_Z_reg;
    assign h_T = h_T_reg;
    assign done = done_reg;
    
endmodule