module Ed25519_TOP (
  input  logic         clk,
  input  logic         rst,               // Active low reset
  input  logic         start,             // Active high start signal

  // Outputs
  output logic         valid,             // Active high valid output
  output logic [255:0] pubkey_out        // Generated public key (KeyGen)
);

  // State Machine
  typedef enum logic [1:0] {
    ST_IDLE         = 2'd0,
    ST_KEYGEN       = 2'd1,
    ST_DONE         = 2'd2
  } state_e;
  
  state_e cs, ns;
  
  // Internal Signals for FSM
  logic         fsm_start, fsm_done;
  logic [1:0]   fsm_opmode;
  logic [511:0] fsm_output_data;
  logic [255:0] fsm_pubkey_out;

  // Register File Wires
  logic [511:0] reg_verify_message, reg_verify_signature, reg_generated_privkey, reg_sign_message, reg_generated_signature;
  logic [255:0] reg_verify_pubkey, reg_generated_pubkey;
  
  // Register file control
  logic         reg_write_en;
  logic [2:0]   reg_addr;
  logic [511:0] reg_write_data;

  // Register File Instance
  Reg_File u_Reg_File (
    .clk(clk),
    .rst(rst),
    .write_en(reg_write_en),
    .addr(reg_addr),
    .write_data(reg_write_data),
    .REG_A1(reg_verify_message),    // 512-bit message for verification
    .REG_A2(reg_verify_signature),  // 512-bit signature for verification
    .REG_A3(reg_verify_pubkey),     // 256-bit public key for verification
    .REG_B1(reg_generated_privkey), // 512-bit generated private key
    .REG_B2(reg_generated_pubkey),  // 256-bit generated public key
    .REG_C1(reg_sign_message),      // 512-bit message to be signed
    .REG_C2(reg_generated_signature)// 512-bit generated signature
  );
  
  // Ed25519 FSM Instance
  ed25519_fsm_top u_ed25519_fsm_top (
    .clk(clk),
    .rst(rst),
    .opmode(2'b00),
    .start(fsm_start),
    .V_message(reg_verify_message),
    .V_sig(reg_verify_signature),
    .V_Pubkey(reg_verify_pubkey),
    .Seckey(reg_generated_privkey),
    .Pubkey(reg_generated_pubkey),
    .S_message(reg_sign_message),
    .done(fsm_done),
    .output_data(fsm_output_data),
    .pubkey_out(fsm_pubkey_out)
  );
  
  // Next-State Logic
  always_comb begin
    ns = cs;  // Default: stay in current state
    case (cs)
      ST_IDLE: begin
        if (start) begin
          ns = ST_KEYGEN;
        end
      end
      
      ST_KEYGEN: begin
        if (fsm_done) ns = ST_DONE;
      end
      
      
      ST_DONE: begin
        ns = ST_IDLE;  // Return to idle after one cycle
      end

      default: ns = ST_IDLE;
    endcase
  end

  // Sequential Logic
  always_ff @(posedge clk or negedge rst) begin
    if (!rst) begin
      cs <= ST_IDLE;
      valid <= 1'b0;
      pubkey_out <= 256'b0;
    end 
    else begin
      cs <= ns;
      // Output logic based on current state
      case (cs)
        ST_DONE: begin
          valid <= 1'b1;
          pubkey_out <= fsm_pubkey_out;
        end
        default: begin
          valid <= 1'b0;
          pubkey_out <= 256'b0;
        end
      endcase
    end
  end

  // Control Logic for Register File and FSM
  always_comb begin
    // Default values
    fsm_start = 1'b0;
    reg_write_en = 1'b0;
    reg_addr = 3'b000;
    reg_write_data = 512'b0;

    case (cs)
      ST_IDLE: begin
        if (start) begin
          fsm_start = 1'b1;
        end
      end
      
      ST_KEYGEN: begin
        if (fsm_done) begin
          // Store generated private key
          reg_write_en = 1'b1;
          reg_addr = 3'b011;  // generated_privkey
          reg_write_data = fsm_output_data;
        end
      end
      
      ST_DONE: begin
        // Store generated public key when completing keygen
          reg_write_en = 1'b1;
          reg_addr = 3'b100;  // generated_pubkey
          reg_write_data = {256'b0, fsm_pubkey_out};
      end
      
      default: begin
        fsm_start = 1'b0;
        reg_write_en = 1'b0;
        reg_addr = 3'b000;
        reg_write_data = 512'b0;
      end
    endcase
  end

endmodule