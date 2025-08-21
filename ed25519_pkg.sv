package ed25519_pkg;

    // Top Module State Parameters
    parameter ST_IDLE         = 6'd0;
    // Key Gen
    parameter ST_KEYGEN_START = 6'd1; parameter ST_KEYGEN_WAIT = 6'd2; parameter ST_KEYGEN_STORE_PRIV = 6'd3; parameter ST_KEYGEN_STORE_PUB = 6'd4;
    // Sign
    parameter ST_SIGN_MSG_LOW = 6'd5; parameter ST_SIGN_MSG_HIGH = 6'd6; parameter ST_SIGN_START = 6'd7; parameter ST_SIGN_WAIT = 6'd8; parameter ST_SIGN_SEND_LOW = 6'd9; parameter ST_SIGN_SEND_HIGH = 6'd10;
    // Verify
    parameter ST_VERIFY_PK    = 6'd11; parameter ST_VERIFY_MSG_LOW = 6'd12; parameter ST_VERIFY_MSG_HIGH = 6'd13; parameter ST_VERIFY_SIG_LOW = 6'd14; parameter ST_VERIFY_SIG_HIGH = 6'd15; parameter ST_VERIFY_START = 6'd16; parameter ST_VERIFY_WAIT = 6'd17; parameter ST_VERIFY_FINALIZE = 6'd18;

    // FSM State Parameters
    parameter FSM_ST_IDLE              = 6'd0;
    // KeyGen states
    parameter FSM_ST_KEYGEN_RNG        = 6'd1; parameter FSM_ST_KEYGEN_HASH = 6'd2; parameter FSM_ST_KEYGEN_CLAMP = 6'd3; parameter FSM_ST_KEYGEN_SCALARMULT = 6'd4; parameter FSM_ST_KEYGEN_TOBYTES = 6'd5; parameter FSM_ST_KEYGEN_FINALIZE = 6'd6;
    // Sign states
    parameter FSM_ST_SIGN_NONCE_HASH   = 6'd7; parameter FSM_ST_SIGN_NONCE_REDUCE = 6'd8; parameter FSM_ST_SIGN_SCALARMULT = 6'd9; parameter FSM_ST_SIGN_R_TOBYTES = 6'd10; parameter FSM_ST_SIGN_HRAM_HASH = 6'd11; parameter FSM_ST_SIGN_HRAM_REDUCE  = 6'd12; parameter FSM_ST_SIGN_MULADD = 6'd13; parameter FSM_ST_SIGN_FINALIZE = 6'd14;
    // Verify states
    parameter FSM_ST_VERIFY_FROMBYTES  = 6'd15; parameter FSM_ST_VERIFY_H_HASH = 6'd16; parameter FSM_ST_VERIFY_H_REDUCE = 6'd17;  parameter FSM_ST_VERIFY_DSCM = 6'd18; parameter FSM_ST_VERIFY_TOBYTES = 6'd19;  parameter FSM_ST_VERIFY_COMPARE = 6'd20; parameter FSM_ST_VERIFY_FINALIZE = 6'd21;

    class ed25519_class;
        bit clk;
        logic [5:0] top_state_cv;
        logic [5:0] fsm_state_cv;
        
        // Randomized inputs
        rand logic rst;
        rand logic [1:0] opmode;
        rand logic start;
        rand logic [511:0] data_in;

        constraint Input_c {
            // Reset constraint - mostly high
            rst dist {1'b1:=99, 1'b0:=1};
            
            // Operation mode distribution
            opmode dist {
                2'b00:=25,  // KeyGen
                2'b01:=35,  // Sign  
                2'b10:=35,  // Verify
                2'b11:=5    // Invalid
            };
            
            // Start signal constraints based on top module state
            if (top_state_cv == ST_IDLE) {
                start dist {1'b1:=90, 1'b0:=10};
            } else {
                start dist {1'b1:=5, 1'b0:=95};  // Low probability in other states
            }
        }

        covergroup cvr_gp @(posedge clk);
            
            // Top Module State Coverage
            top_state_cp: coverpoint top_state_cv {
                bins IDLE_state = {ST_IDLE};
                
                // KeyGen states
                bins KEYGEN_START_state      = {ST_KEYGEN_START};
                bins KEYGEN_WAIT_state       = {ST_KEYGEN_WAIT};
                bins KEYGEN_STORE_PRIV_state = {ST_KEYGEN_STORE_PRIV};
                bins KEYGEN_STORE_PUB_state  = {ST_KEYGEN_STORE_PUB};
                
                // Sign states  
                bins SIGN_MSG_LOW_state  = {ST_SIGN_MSG_LOW};
                bins SIGN_MSG_HIGH_state = {ST_SIGN_MSG_HIGH};
                bins SIGN_START_state    = {ST_SIGN_START};
                bins SIGN_WAIT_state     = {ST_SIGN_WAIT};
                bins SIGN_SEND_LOW_state = {ST_SIGN_SEND_LOW};
                bins SIGN_SEND_HIGH_state = {ST_SIGN_SEND_HIGH};
                
                // Verify states
                bins VERIFY_PK_state       = {ST_VERIFY_PK};
                bins VERIFY_MSG_LOW_state  = {ST_VERIFY_MSG_LOW};
                bins VERIFY_MSG_HIGH_state = {ST_VERIFY_MSG_HIGH};
                bins VERIFY_SIG_LOW_state  = {ST_VERIFY_SIG_LOW};
                bins VERIFY_SIG_HIGH_state = {ST_VERIFY_SIG_HIGH};
                bins VERIFY_START_state    = {ST_VERIFY_START};
                bins VERIFY_WAIT_state     = {ST_VERIFY_WAIT};
                bins VERIFY_FINALIZE_state = {ST_VERIFY_FINALIZE};
            }
            
            // Top Module State Transitions
            top_state_trans_cp: coverpoint top_state_cv {
                bins IDLE_to_KEYGEN_START = (ST_IDLE => ST_KEYGEN_START);
                bins IDLE_to_SIGN_MSG_LOW = (ST_IDLE => ST_SIGN_MSG_LOW);
                bins IDLE_to_VERIFY_PK = (ST_IDLE => ST_VERIFY_PK);
                
                // KeyGen flow
                bins KEYGEN_START_to_WAIT = (ST_KEYGEN_START => ST_KEYGEN_WAIT);
                bins KEYGEN_WAIT_to_STORE_PRIV = (ST_KEYGEN_WAIT => ST_KEYGEN_STORE_PRIV);
                bins KEYGEN_STORE_PRIV_to_STORE_PUB = (ST_KEYGEN_STORE_PRIV => ST_KEYGEN_STORE_PUB);
                bins KEYGEN_STORE_PUB_to_IDLE = (ST_KEYGEN_STORE_PUB => ST_IDLE);
                
                // Sign flow
                bins SIGN_MSG_LOW_to_HIGH = (ST_SIGN_MSG_LOW => ST_SIGN_MSG_HIGH);
                bins SIGN_MSG_HIGH_to_START = (ST_SIGN_MSG_HIGH => ST_SIGN_START);
                bins SIGN_START_to_WAIT = (ST_SIGN_START => ST_SIGN_WAIT);
                bins SIGN_WAIT_to_SEND_LOW = (ST_SIGN_WAIT => ST_SIGN_SEND_LOW);
                bins SIGN_SEND_LOW_to_HIGH = (ST_SIGN_SEND_LOW => ST_SIGN_SEND_HIGH);
                bins SIGN_SEND_HIGH_to_IDLE = (ST_SIGN_SEND_HIGH => ST_IDLE);
                
                // Verify flow
                bins VERIFY_PK_to_MSG_LOW = (ST_VERIFY_PK => ST_VERIFY_MSG_LOW);
                bins VERIFY_MSG_LOW_to_HIGH = (ST_VERIFY_MSG_LOW => ST_VERIFY_MSG_HIGH);
                bins VERIFY_MSG_HIGH_to_SIG_LOW = (ST_VERIFY_MSG_HIGH => ST_VERIFY_SIG_LOW);
                bins VERIFY_SIG_LOW_to_HIGH = (ST_VERIFY_SIG_LOW => ST_VERIFY_SIG_HIGH);
                bins VERIFY_SIG_HIGH_to_START = (ST_VERIFY_SIG_HIGH => ST_VERIFY_START);
                bins VERIFY_START_to_WAIT = (ST_VERIFY_START => ST_VERIFY_WAIT);
                bins VERIFY_WAIT_to_FINALIZE = (ST_VERIFY_WAIT => ST_VERIFY_FINALIZE);
                bins VERIFY_FINALIZE_to_IDLE = (ST_VERIFY_FINALIZE => ST_IDLE);
            }
            
            // FSM State Coverage
            fsm_state_cp: coverpoint fsm_state_cv {
                bins FSM_IDLE_state = {FSM_ST_IDLE};
                
                // KeyGen FSM states
                bins FSM_KEYGEN_RNG_state        = {FSM_ST_KEYGEN_RNG};
                bins FSM_KEYGEN_HASH_state       = {FSM_ST_KEYGEN_HASH};
                bins FSM_KEYGEN_CLAMP_state      = {FSM_ST_KEYGEN_CLAMP};
                bins FSM_KEYGEN_SCALARMULT_state = {FSM_ST_KEYGEN_SCALARMULT};
                bins FSM_KEYGEN_TOBYTES_state    = {FSM_ST_KEYGEN_TOBYTES};
                bins FSM_KEYGEN_FINALIZE_state   = {FSM_ST_KEYGEN_FINALIZE};
                
                // Sign FSM states
                bins FSM_SIGN_NONCE_HASH_state   = {FSM_ST_SIGN_NONCE_HASH};
                bins FSM_SIGN_NONCE_REDUCE_state = {FSM_ST_SIGN_NONCE_REDUCE};
                bins FSM_SIGN_SCALARMULT_state   = {FSM_ST_SIGN_SCALARMULT};
                bins FSM_SIGN_R_TOBYTES_state    = {FSM_ST_SIGN_R_TOBYTES};
                bins FSM_SIGN_HRAM_HASH_state    = {FSM_ST_SIGN_HRAM_HASH};
                bins FSM_SIGN_HRAM_REDUCE_state  = {FSM_ST_SIGN_HRAM_REDUCE};
                bins FSM_SIGN_MULADD_state       = {FSM_ST_SIGN_MULADD};
                bins FSM_SIGN_FINALIZE_state     = {FSM_ST_SIGN_FINALIZE};
                
                // Verify FSM states
                bins FSM_VERIFY_FROMBYTES_state  = {FSM_ST_VERIFY_FROMBYTES};
                bins FSM_VERIFY_H_HASH_state     = {FSM_ST_VERIFY_H_HASH};
                bins FSM_VERIFY_H_REDUCE_state   = {FSM_ST_VERIFY_H_REDUCE};
                bins FSM_VERIFY_DSCM_state       = {FSM_ST_VERIFY_DSCM};
                bins FSM_VERIFY_TOBYTES_state    = {FSM_ST_VERIFY_TOBYTES};
                bins FSM_VERIFY_COMPARE_state    = {FSM_ST_VERIFY_COMPARE};
                bins FSM_VERIFY_FINALIZE_state   = {FSM_ST_VERIFY_FINALIZE};
            }
            
            // FSM State Transitions 
            fsm_state_trans_cp: coverpoint fsm_state_cv {
                // KeyGen FSM transitions
                bins FSM_IDLE_to_KEYGEN_RNG = (FSM_ST_IDLE => FSM_ST_KEYGEN_RNG);
                bins FSM_KEYGEN_RNG_to_HASH = (FSM_ST_KEYGEN_RNG => FSM_ST_KEYGEN_HASH);
                bins FSM_KEYGEN_HASH_to_CLAMP = (FSM_ST_KEYGEN_HASH => FSM_ST_KEYGEN_CLAMP);
                bins FSM_KEYGEN_CLAMP_to_SCALARMULT = (FSM_ST_KEYGEN_CLAMP => FSM_ST_KEYGEN_SCALARMULT);
                bins FSM_KEYGEN_SCALARMULT_to_TOBYTES = (FSM_ST_KEYGEN_SCALARMULT => FSM_ST_KEYGEN_TOBYTES);
                bins FSM_KEYGEN_TOBYTES_to_FINALIZE = (FSM_ST_KEYGEN_TOBYTES => FSM_ST_KEYGEN_FINALIZE);
                bins FSM_KEYGEN_FINALIZE_to_IDLE = (FSM_ST_KEYGEN_FINALIZE => FSM_ST_IDLE);
                
                // Sign FSM transitions
                bins FSM_IDLE_to_SIGN_NONCE_HASH = (FSM_ST_IDLE => FSM_ST_SIGN_NONCE_HASH);
                bins FSM_SIGN_NONCE_HASH_to_REDUCE = (FSM_ST_SIGN_NONCE_HASH => FSM_ST_SIGN_NONCE_REDUCE); 
                bins FSM_SIGN_NONCE_REDUCE_to_SCALARMULT = (FSM_ST_SIGN_NONCE_REDUCE => FSM_ST_SIGN_SCALARMULT);
                bins FSM_SIGN_SCALARMULT_to_R_TOBYTES = (FSM_ST_SIGN_SCALARMULT => FSM_ST_SIGN_R_TOBYTES);
                bins FSM_SIGN_R_TOBYTES_to_HRAM_HASH = (FSM_ST_SIGN_R_TOBYTES => FSM_ST_SIGN_HRAM_HASH);
                bins FSM_SIGN_HRAM_HASH_to_REDUCE = (FSM_ST_SIGN_HRAM_HASH => FSM_ST_SIGN_HRAM_REDUCE);
                bins FSM_SIGN_HRAM_REDUCE_to_MULADD = (FSM_ST_SIGN_HRAM_REDUCE => FSM_ST_SIGN_MULADD);
                bins FSM_SIGN_MULADD_to_FINALIZE = (FSM_ST_SIGN_MULADD => FSM_ST_SIGN_FINALIZE);
                bins FSM_SIGN_FINALIZE_to_IDLE = (FSM_ST_SIGN_FINALIZE => FSM_ST_IDLE);
                
                // Verify FSM transitions
                bins FSM_IDLE_to_VERIFY_FROMBYTES = (FSM_ST_IDLE => FSM_ST_VERIFY_FROMBYTES);
                bins FSM_VERIFY_FROMBYTES_to_H_HASH = (FSM_ST_VERIFY_FROMBYTES => FSM_ST_VERIFY_H_HASH);
                bins FSM_VERIFY_FROMBYTES_to_FINALIZE = (FSM_ST_VERIFY_FROMBYTES => FSM_ST_VERIFY_FINALIZE); // Error path
                bins FSM_VERIFY_H_HASH_to_REDUCE = (FSM_ST_VERIFY_H_HASH => FSM_ST_VERIFY_H_REDUCE);
                bins FSM_VERIFY_H_REDUCE_to_DSCM = (FSM_ST_VERIFY_H_REDUCE => FSM_ST_VERIFY_DSCM);
                bins FSM_VERIFY_DSCM_to_TOBYTES = (FSM_ST_VERIFY_DSCM => FSM_ST_VERIFY_TOBYTES);
                bins FSM_VERIFY_TOBYTES_to_COMPARE = (FSM_ST_VERIFY_TOBYTES => FSM_ST_VERIFY_COMPARE);
                bins FSM_VERIFY_COMPARE_to_FINALIZE = (FSM_ST_VERIFY_COMPARE => FSM_ST_VERIFY_FINALIZE);
                bins FSM_VERIFY_FINALIZE_to_IDLE = (FSM_ST_VERIFY_FINALIZE => FSM_ST_IDLE);
            }
            
            // Input Signal Coverage
            opcode_cp: coverpoint opmode {
                bins KEYGEN_op = {2'b00};
                bins SIGN_op   = {2'b01};
                bins VERIFY_op = {2'b10};
                bins INVALID_op = {2'b11};
            }
            
            start_cp: coverpoint start;
            rst_cp: coverpoint rst;
            
            // Cross Coverage - Operation mode with Top States
            opmode_cross_top_state: cross opcode_cp, top_state_cp {
                // KeyGen operation should only see KeyGen states + IDLE
                ignore_bins invalid_keygen = binsof(opcode_cp.KEYGEN_op) && 
                    (binsof(top_state_cp.SIGN_MSG_LOW_state) || binsof(top_state_cp.SIGN_MSG_HIGH_state) ||
                     binsof(top_state_cp.SIGN_START_state) || binsof(top_state_cp.SIGN_WAIT_state) ||
                     binsof(top_state_cp.SIGN_SEND_LOW_state) || binsof(top_state_cp.SIGN_SEND_HIGH_state) ||
                     binsof(top_state_cp.VERIFY_PK_state) || binsof(top_state_cp.VERIFY_MSG_LOW_state) ||
                     binsof(top_state_cp.VERIFY_MSG_HIGH_state) || binsof(top_state_cp.VERIFY_SIG_LOW_state) ||
                     binsof(top_state_cp.VERIFY_SIG_HIGH_state) || binsof(top_state_cp.VERIFY_START_state) ||
                     binsof(top_state_cp.VERIFY_WAIT_state) || binsof(top_state_cp.VERIFY_FINALIZE_state));
                     
                // Similar constraints for SIGN and VERIFY operations
                ignore_bins invalid_sign = binsof(opcode_cp.SIGN_op) && 
                    (binsof(top_state_cp.KEYGEN_START_state) || binsof(top_state_cp.KEYGEN_WAIT_state) ||
                     binsof(top_state_cp.KEYGEN_STORE_PRIV_state) || binsof(top_state_cp.KEYGEN_STORE_PUB_state) ||
                     binsof(top_state_cp.VERIFY_PK_state) || binsof(top_state_cp.VERIFY_MSG_LOW_state) ||
                     binsof(top_state_cp.VERIFY_MSG_HIGH_state) || binsof(top_state_cp.VERIFY_SIG_LOW_state) ||
                     binsof(top_state_cp.VERIFY_SIG_HIGH_state) || binsof(top_state_cp.VERIFY_START_state) ||
                     binsof(top_state_cp.VERIFY_WAIT_state) || binsof(top_state_cp.VERIFY_FINALIZE_state));
                     
                ignore_bins invalid_verify = binsof(opcode_cp.VERIFY_op) && 
                    (binsof(top_state_cp.KEYGEN_START_state) || binsof(top_state_cp.KEYGEN_WAIT_state) ||
                     binsof(top_state_cp.KEYGEN_STORE_PRIV_state) || binsof(top_state_cp.KEYGEN_STORE_PUB_state) ||
                     binsof(top_state_cp.SIGN_MSG_LOW_state) || binsof(top_state_cp.SIGN_MSG_HIGH_state) ||
                     binsof(top_state_cp.SIGN_START_state) || binsof(top_state_cp.SIGN_WAIT_state) ||
                     binsof(top_state_cp.SIGN_SEND_LOW_state) || binsof(top_state_cp.SIGN_SEND_HIGH_state));

                ignore_bins invalid_opcode = binsof(opcode_cp.INVALID_op);
            }
            
            // Cross Coverage - Start signal with states
            start_cross_top_state: cross start_cp, top_state_cp;
        endgroup

        function new();
            cvr_gp = new();
        endfunction
        
    endclass

endpackage