module ed25519_fsm_top (
    input  logic          clk,
    input  logic          rst,          // Active low reset
    input  logic [1:0]    opmode,       // 00: KeyGen, 01: Sign, 10: Verify
    input  logic          start,        // Active high start signal
    input  logic [511:0]  V_message,    // Input message for verification
    input  logic [511:0]  V_sig,        // Signature to be verified
    input  logic [255:0]  V_Pubkey,     // Public key for signature verification
    input  logic [511:0]  Seckey,       // Generated private key (512-bit)
    input  logic [255:0]  Pubkey,       // Generated public key (from keygen)
    input  logic [511:0]  S_message,    // Input message for signature
    output logic          done,         // Active high done signal
    output logic [511:0]  output_data,  // KeyGen: private key; Sign: signature; Verify: 512'hFFFF... if valid, else 0.
    output logic [255:0]  pubkey_out    // Used in KeyGen mode (public key)
);

  //===========================================================================
  // State Declaration
  //===========================================================================
  typedef enum logic [3:0] {
    ST_IDLE              = 3'd0,
    // KeyGen states (opmode == 00)
    ST_KEYGEN_RNG        = 3'd1,
    ST_KEYGEN_HASH       = 3'd2,
    ST_KEYGEN_CLAMP      = 3'd3,
    ST_KEYGEN_SCALARMULT = 3'd4,
    ST_KEYGEN_TOBYTES    = 3'd5,
    ST_KEYGEN_FINALIZE   = 3'd6
  } state_e;
  
  state_e cs, ns, prev_cs;

  //===========================================================================
  // Internal Control Signals
  //===========================================================================
  // Start signals for submodules
  logic start_hash, start_scalarmult, start_tobytes;

  
  // Done signals from submodules
  logic hash_done, scalarmult_done, tobytes_done;

  //===========================================================================
  // Internal Data Wires
  //===========================================================================
  // LFSR
  logic [255:0] lfsr_out;
  logic [255:0] RNG_out;
  always_ff @(posedge clk or negedge rst) begin
    if(~rst) begin
      RNG_out <= 256'b0;
    end 
    else if (cs == ST_KEYGEN_RNG) begin
      // Take The random seed 
      RNG_out <= lfsr_out;
    end
  end


  // SHA512
  logic [511:0] hash_out;     // SHA512 hash output


  
  // Mode for SHA512_Mux: 
  //  2'b00 for keygen, 2'b01 for nonce hash, 2'b10 for hram/verification hash.
  logic [1:0] sha512_mux_mode;
  always @(*) begin
    sha512_mux_mode = 2'b00;
  end
  
  // Output of seckey clamp
  logic [511:0] clamped_seckey;
  
  // ge_scalarmult output (point in ge_p3 format)
  logic signed [319:0] scalarmult_out_X, scalarmult_out_Y, scalarmult_out_Z, scalarmult_out_T;
  
  // ge_p3_tobytes output
  logic [7:0] tobytes_out [31:0];
  // We'll use the lower 256 bits as the compressed representation (R_bytes)
  logic [255:0] R_bytes;
  assign R_bytes = {tobytes_out[31], tobytes_out[30], tobytes_out[29], tobytes_out[28],
                    tobytes_out[27], tobytes_out[26], tobytes_out[25], tobytes_out[24],
                    tobytes_out[23], tobytes_out[22], tobytes_out[21], tobytes_out[20],
                    tobytes_out[19], tobytes_out[18], tobytes_out[17], tobytes_out[16],
                    tobytes_out[15], tobytes_out[14], tobytes_out[13], tobytes_out[12],
                    tobytes_out[11], tobytes_out[10], tobytes_out[9],  tobytes_out[8],
                    tobytes_out[7],  tobytes_out[6],  tobytes_out[5],  tobytes_out[4],
                    tobytes_out[3],  tobytes_out[2],  tobytes_out[1],  tobytes_out[0]};
  
  // sc_reduce outputs (for nonce, hram, and verification)
  logic [255:0] nonce_reduced, hram_reduced, verify_h_reduced;
  logic [255:0] reduced_out;
  

  //===========================================================================
  // State Transition Logic
  //===========================================================================
  always_ff @(posedge clk or negedge rst) begin
    if(~rst) begin
      cs <= ST_IDLE;
    end 
    else begin
      cs <= ns;  // Update state
    end
  end

  //===========================================================================
  // Next-State Logic (Combinational)
  //===========================================================================
  always @(*) begin
    ns = cs;  // Default: stay in current state
    case (cs)
      ST_IDLE: begin
        if (start) begin
          case (opmode)
            2'b00: ns = ST_KEYGEN_RNG ;
            default: ns = ST_IDLE;
          endcase
        end
        else ns = ST_IDLE;
      end

      // -------- Key Generation Flow (opmode == 00) --------
      ST_KEYGEN_RNG : ns = ST_KEYGEN_HASH;  // LFSR runs continuously
      ST_KEYGEN_HASH:    if (hash_done) ns = ST_KEYGEN_CLAMP;
      ST_KEYGEN_CLAMP:                   ns = ST_KEYGEN_SCALARMULT;
      ST_KEYGEN_SCALARMULT: if (scalarmult_done) ns = ST_KEYGEN_TOBYTES;
      ST_KEYGEN_TOBYTES: if (tobytes_done) ns = ST_KEYGEN_FINALIZE;
      ST_KEYGEN_FINALIZE:                ns = ST_IDLE;
      
      default: ns = ST_IDLE;
    endcase
  end


  //===========================================================================
  // Sequential Output & Control Signals Logic
  //===========================================================================
  always_ff @(posedge clk or negedge rst) begin
    if (!rst) begin
      // Clear all start signals
      start_hash         <= 1'b0;
      start_scalarmult   <= 1'b0;
      start_tobytes      <= 1'b0;
      // Clear outputs
      done               <= 1'b0;
      output_data        <= 512'b0;
      pubkey_out         <= 256'b0;
    end
    else begin
      // Default: deassert all start signals and done
      start_hash         <= 1'b0;
      start_scalarmult   <= 1'b0;
      start_tobytes      <= 1'b0;
      done               <= 1'b0;
      
      case (cs)
        ST_IDLE: begin
          // Remain idle.
        end

        // -------- Key Generation Flow --------
        ST_KEYGEN_RNG : begin
          // LFSR runs continuously.
        end
        ST_KEYGEN_HASH: begin
          start_hash <= (prev_cs != ST_KEYGEN_HASH);
          // SHA512_Mux in keygen mode uses:
          //    sha512_mux_random = lfsr_out, mode = 2'b00.
        end
        ST_KEYGEN_CLAMP: begin
          // Clamp the hash_out to produce the expanded secret key.
        end
        ST_KEYGEN_SCALARMULT: begin
          start_scalarmult <= (prev_cs != ST_KEYGEN_SCALARMULT);
          // Use lower 256 bits of clamped_seckey as scalar input.
        end
        ST_KEYGEN_TOBYTES: begin
          start_tobytes <= (prev_cs != ST_KEYGEN_TOBYTES);
          // Convert the ge_p3 point to byte format.
        end
        ST_KEYGEN_FINALIZE: begin
          // Finalize keygen: output clamped secret key and computed public key.
          output_data <= clamped_seckey;
          pubkey_out  <= R_bytes;
          done        <= 1'b1;
        end
        
        default: begin
          // Default: no action.
        end
      endcase
    end
  end

  always_ff @(posedge clk or negedge rst) begin 
    if(~rst) begin
      prev_cs <= ST_IDLE;
    end else begin
      prev_cs <= cs;
    end
  end

  //===========================================================================
  // Submodule Instantiations
  //===========================================================================

  // --- LFSR for KeyGen ---
  LFSR_256bit u_LFSR (
      .clk(clk),
      .rst(rst),
      .random_num(lfsr_out)
  );

  // --- SHA512_Mux ---
  SHA512_wrapper_mux u_SHA512_Wrapper (
      .clk(clk),
      .rst(rst),
      .start_sha512(start_hash),
      .sha512_mode(sha512_mux_mode), // selects Mux mode *and* is passed to the SHA core
      .hash_message_in(),
      .random_number(RNG_out),
      .hash_pubkey_in(),
      .R(),
      .seckey32_in(),
      .end_sha512(hash_done),
      .hash(hash_out)
  );
  
  // --- seckey_clamp ---
  seckey_clamp u_seckey_clamp (
      .input_hashed_seckey(hash_out),
      .output_sk(clamped_seckey)
  );
  
  // --- ge_scalarmult_base ---
  ge_scalarmult_base u_ge_scalarmult_base (
      .clk(clk),
      .reset(rst),
      .a(clamped_seckey[255:0]), // Use lower 256 bits of clamped secret key
      .start(start_scalarmult),
      .h_X(scalarmult_out_X),
      .h_Y(scalarmult_out_Y),
      .h_Z(scalarmult_out_Z),
      .h_T(scalarmult_out_T),
      .done(scalarmult_done)
  );
  
  // --- ge_p3_tobytes ---
  ge_p3_tobytes u_ge_p3_tobytes (
      .clk(clk),
      .rst(rst),
      .start(start_tobytes),
      .X(scalarmult_out_X),
      .Y(scalarmult_out_Y),
      .Z(scalarmult_out_Z),
      .s(tobytes_out),
      .done(tobytes_done)
  );

endmodule
