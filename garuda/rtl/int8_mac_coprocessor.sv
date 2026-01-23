// INT8 MAC coprocessor top-level module
// Connects to CVA6 via CVXIF interface

module int8_mac_coprocessor
  import int8_mac_instr_pkg::*;
#(
    parameter  int unsigned NrRgprPorts         = 2,
    parameter  int unsigned XLEN                = 32,
    parameter  type         readregflags_t      = logic,
    parameter  type         writeregflags_t     = logic,
    parameter  type         id_t                = logic,
    parameter  type         hartid_t            = logic,
    parameter  type         x_compressed_req_t  = logic,
    parameter  type         x_compressed_resp_t = logic,
    parameter  type         x_issue_req_t       = logic,
    parameter  type         x_issue_resp_t      = logic,
    parameter  type         x_register_t        = logic,
    parameter  type         x_commit_t          = logic,
    parameter  type         x_result_t          = logic,
    parameter  type         cvxif_req_t         = logic,
    parameter  type         cvxif_resp_t        = logic,
    localparam type         registers_t         = logic [NrRgprPorts-1:0][XLEN-1:0]
) (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  cvxif_req_t  cvxif_req_i,
    output cvxif_resp_t cvxif_resp_o
);

  x_compressed_req_t  compressed_req;
  x_compressed_resp_t compressed_resp;
  logic               compressed_valid, compressed_ready;
  
  x_issue_req_t       issue_req;
  x_issue_resp_t      issue_resp;
  logic               issue_valid, issue_ready;
  
  x_register_t        register;
  logic               register_valid;
  
  registers_t         registers;
  opcode_t            opcode;
  hartid_t            issue_hartid, hartid;
  id_t                issue_id, id;
  logic [4:0]         issue_rd, rd;
  
  logic [XLEN-1:0]    result;
  logic               result_valid;
  logic               we;
  logic               overflow;  // Overflow/saturation flag

  // Attention microkernel engine signals
  localparam int unsigned MAX_K = 256;
  localparam int unsigned WORD_ELEMS = 4;
  
  logic                    mk_cfg_valid;
  logic [$clog2(MAX_K+1)-1:0] mk_cfg_k;
  logic signed [15:0]         mk_cfg_scale;
  logic [3:0]                mk_cfg_shift;
  logic signed [31:0]        mk_cfg_clip_min, mk_cfg_clip_max;
  logic                      mk_cfg_en_scale, mk_cfg_en_clip;
  
  logic                      mk_load_q_valid;
  logic [$clog2((MAX_K+WORD_ELEMS-1)/WORD_ELEMS)-1:0] mk_load_q_idx;
  logic [31:0]               mk_load_q_word;
  
  logic                      mk_load_k_valid;
  logic [$clog2((MAX_K+WORD_ELEMS-1)/WORD_ELEMS)-1:0] mk_load_k_idx;
  logic [31:0]               mk_load_k_word;
  
  logic                      mk_start;
  logic                      mk_busy;
  logic                      mk_done;
  logic                      mk_result_valid;
  logic signed [31:0]        mk_result;
  
  // Microkernel state machine for operand staging
  localparam int unsigned MAX_WORDS = (MAX_K + WORD_ELEMS - 1) / WORD_ELEMS;
  logic [$clog2(MAX_WORDS)-1:0] mk_k_words;
  logic [$clog2(MAX_WORDS)-1:0] mk_current_word_idx;
  
  // Latched configuration values (persist across instructions)
  logic [$clog2(MAX_K+1)-1:0] mk_latched_k;
  logic signed [31:0] mk_latched_clip_min, mk_latched_clip_max;
  
  // Selection between regular MAC unit and microkernel engine
  logic use_microkernel;

  assign compressed_req    = cvxif_req_i.compressed_req;
  assign compressed_valid  = cvxif_req_i.compressed_valid;
  assign compressed_ready  = 1'b1;
  assign compressed_resp   = x_compressed_resp_t'(0);
  
  assign issue_req         = cvxif_req_i.issue_req;
  assign issue_valid       = cvxif_req_i.issue_valid;
  assign register          = cvxif_req_i.register;
  assign register_valid    = cvxif_req_i.register_valid;
  
  assign cvxif_resp_o.compressed_ready = compressed_ready;
  assign cvxif_resp_o.compressed_resp  = compressed_resp;
  assign cvxif_resp_o.issue_ready      = issue_ready;
  assign cvxif_resp_o.issue_resp       = issue_resp;
  assign cvxif_resp_o.register_ready   = cvxif_resp_o.issue_ready;

  int8_mac_decoder #(
      .copro_issue_resp_t(copro_issue_resp_t),
      .opcode_t          (opcode_t),
      .NbInstr           (NbInstr),
      .CoproInstr        (int8_mac_instr_pkg::CoproInstr),
      .NrRgprPorts       (NrRgprPorts),
      .hartid_t          (hartid_t),
      .id_t              (id_t),
      .x_issue_req_t     (x_issue_req_t),
      .x_issue_resp_t    (x_issue_resp_t),
      .x_register_t      (x_register_t),
      .registers_t       (registers_t)
  ) i_int8_mac_decoder (
      .clk_i            (clk_i),
      .rst_ni           (rst_ni),
      .issue_valid_i    (issue_valid),
      .issue_req_i      (issue_req),
      .issue_ready_o    (issue_ready),
      .issue_resp_o     (issue_resp),
      .register_valid_i (register_valid),
      .register_i       (register),
      .registers_o      (registers),
      .opcode_o         (opcode),
      .hartid_o         (issue_hartid),
      .id_o             (issue_id),
      .rd_o             (issue_rd)
  );

  // Determine if we should use microkernel engine
  assign use_microkernel = (opcode inside {ATT_DOT_SETUP, ATT_DOT_RUN, ATT_DOT_RUN_SCALE, ATT_DOT_RUN_CLIP});

  int8_mac_unit #(
      .XLEN      (XLEN),
      .opcode_t  (opcode_t),
      .hartid_t  (hartid_t),
      .id_t      (id_t)
  ) i_int8_mac_unit (
      .clk_i      (clk_i),
      .rst_ni     (rst_ni),
      .rs1_i      (registers[0]),
      .rs2_i      (registers[1]),
      .rd_i       (registers[0]),
      .opcode_i   (opcode),
      .hartid_i   (issue_hartid),
      .id_i       (issue_id),
      .rd_addr_i  (issue_rd),
      .result_o   (result),
      .valid_o    (result_valid),
      .we_o       (we),
      .overflow_o (overflow),
      .rd_addr_o  (rd),
      .hartid_o   (hartid),
      .id_o       (id)
  );

  // Attention microkernel engine
  attention_microkernel_engine #(
      .XLEN(XLEN),
      .MAX_K(MAX_K),
      .WORD_ELEMS(WORD_ELEMS)
  ) i_attention_microkernel_engine (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .cfg_valid_i(mk_cfg_valid),
      .cfg_k_i(mk_cfg_k),
      .cfg_scale_i(mk_cfg_scale),
      .cfg_shift_i(mk_cfg_shift),
      .cfg_clip_min_i(mk_cfg_clip_min),
      .cfg_clip_max_i(mk_cfg_clip_max),
      .cfg_enable_scale_i(mk_cfg_en_scale),
      .cfg_enable_clip_i(mk_cfg_en_clip),
      .load_q_valid_i(mk_load_q_valid),
      .load_q_idx_i(mk_load_q_idx),
      .load_q_word_i(mk_load_q_word),
      .load_k_valid_i(mk_load_k_valid),
      .load_k_idx_i(mk_load_k_idx),
      .load_k_word_i(mk_load_k_word),
      .start_i(mk_start),
      .busy_o(mk_busy),
      .done_o(mk_done),
      .result_valid_o(mk_result_valid),
      .result_o(mk_result)
  );

  // Microkernel control logic - handles multi-cycle operand staging
  typedef enum logic [1:0] {
    MK_IDLE,
    MK_STAGING,
    MK_EXECUTING
  } mk_state_t;
  
  mk_state_t mk_state_q, mk_state_d;
  logic signed [15:0] mk_latched_scale;
  logic [3:0] mk_latched_shift;
  logic mk_latched_en_scale, mk_latched_en_clip;
  
  always_comb begin
    mk_state_d = mk_state_q;
    mk_cfg_valid = 1'b0;
    mk_load_q_valid = 1'b0;
    mk_load_k_valid = 1'b0;
    mk_start = 1'b0;
    
      // Default: use latched configuration settings
      mk_cfg_en_scale = mk_latched_en_scale;
      mk_cfg_en_clip = mk_latched_en_clip;
      mk_cfg_scale = mk_latched_scale;
      mk_cfg_shift = mk_latched_shift;
      mk_cfg_k = mk_latched_k;
      mk_cfg_clip_min = mk_latched_clip_min;
      mk_cfg_clip_max = mk_latched_clip_max;
    
    case (mk_state_q)
      MK_IDLE: begin
        // Handle ATT_DOT_SETUP: configure engine
        if (issue_valid && issue_ready && opcode == ATT_DOT_SETUP) begin
          mk_cfg_valid = 1'b1;
          mk_cfg_k = registers[0][$clog2(MAX_K+1)-1:0];  // K from rs1[7:0]
          mk_cfg_shift = registers[0][11:8];              // shift from rs1[11:8]
          mk_cfg_scale = registers[1][15:0];              // scale from rs2[15:0]
          mk_cfg_clip_min = mk_latched_clip_min;          // Use latched values (defaults)
          mk_cfg_clip_max = mk_latched_clip_max;
          mk_cfg_en_scale = 1'b0;  // Setup doesn't enable post-ops (will be updated before execution)
          mk_cfg_en_clip = 1'b0;
          
          mk_k_words = ((registers[0][$clog2(MAX_K+1)-1:0] + (WORD_ELEMS-1)) / WORD_ELEMS);
          mk_state_d = MK_IDLE;  // Stay in IDLE, ready for staging
        end
        
        // Handle ATT_DOT_RUN*: start staging operands
        if (issue_valid && issue_ready && opcode inside {ATT_DOT_RUN, ATT_DOT_RUN_SCALE, ATT_DOT_RUN_CLIP}) begin
          mk_latched_en_scale = (opcode == ATT_DOT_RUN_SCALE || opcode == ATT_DOT_RUN_CLIP);
          mk_latched_en_clip = (opcode == ATT_DOT_RUN_CLIP);
          mk_cfg_en_scale = mk_latched_en_scale;
          mk_cfg_en_clip = mk_latched_en_clip;
          
          // Stage first word pair
          mk_load_q_valid = 1'b1;
          mk_load_q_idx = '0;
          mk_load_q_word = registers[0];  // Q_word from rs1
          
          mk_load_k_valid = 1'b1;
          mk_load_k_idx = '0;
          mk_load_k_word = registers[1];  // K_word from rs2
          
          // Update engine config with scale/clip settings before execution
          mk_cfg_valid = 1'b1;  // Re-assert config to update scale/clip enables
          
          if (mk_k_words == 1) begin
            // Single word, execute immediately
            mk_start = 1'b1;
            mk_state_d = MK_EXECUTING;
            mk_current_word_idx = '0;
          end else begin
            // Multiple words, enter staging state
            mk_state_d = MK_STAGING;
            mk_current_word_idx = 1;  // Next word index
          end
        end
      end
      
      MK_STAGING: begin
        // Continue staging operands (one word pair per instruction)
        if (issue_valid && issue_ready && opcode inside {ATT_DOT_RUN, ATT_DOT_RUN_SCALE, ATT_DOT_RUN_CLIP}) begin
          mk_latched_en_scale = (opcode == ATT_DOT_RUN_SCALE || opcode == ATT_DOT_RUN_CLIP);
          mk_latched_en_clip = (opcode == ATT_DOT_RUN_CLIP);
          mk_cfg_en_scale = mk_latched_en_scale;
          mk_cfg_en_clip = mk_latched_en_clip;
          
          // Stage current word pair
          mk_load_q_valid = 1'b1;
          mk_load_q_idx = mk_current_word_idx;
          mk_load_q_word = registers[0];  // Q_word from rs1
          
          mk_load_k_valid = 1'b1;
          mk_load_k_idx = mk_current_word_idx;
          mk_load_k_word = registers[1];  // K_word from rs2
          
          if (mk_current_word_idx == (mk_k_words - 1)) begin
            // All words staged, update config and trigger execution
            mk_cfg_valid = 1'b1;  // Re-assert config to update scale/clip enables
            mk_start = 1'b1;
            mk_state_d = MK_EXECUTING;
            mk_current_word_idx = '0;
          end else begin
            // More words to stage, increment index
            mk_current_word_idx = mk_current_word_idx + 1;
            mk_state_d = MK_STAGING;
          end
        end
      end
      
      MK_EXECUTING: begin
        // Wait for execution to complete
        mk_cfg_en_scale = mk_latched_en_scale;
        mk_cfg_en_clip = mk_latched_en_clip;
        
        if (mk_done && mk_result_valid) begin
          // Execution complete, return to IDLE
          mk_state_d = MK_IDLE;
          mk_current_word_idx = '0;
        end
      end
      
      default: begin
        mk_state_d = MK_IDLE;
      end
    endcase
  end
  
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mk_state_q <= MK_IDLE;
      mk_k_words <= '0;
      mk_current_word_idx <= '0;
      mk_latched_k <= '0;
      mk_latched_scale <= '0;
      mk_latched_shift <= '0;
      mk_latched_en_scale <= 1'b0;
      mk_latched_en_clip <= 1'b0;
      mk_latched_clip_min <= -32'sd32768;
      mk_latched_clip_max <= 32'sd32767;
    end else begin
      mk_state_q <= mk_state_d;
      
      // Update word index during staging
      if (mk_state_d == MK_STAGING && mk_state_q == MK_IDLE) begin
        // Starting staging, initialize to word 1 (word 0 was staged in comb logic)
        mk_current_word_idx <= 1;
      end else if (mk_state_q == MK_STAGING && mk_state_d == MK_STAGING) begin
        // Continue staging, increment word index
        if (mk_current_word_idx == (mk_k_words - 1)) begin
          // Last word was staged, will transition to EXECUTING
          mk_current_word_idx <= '0;
        end else begin
          mk_current_word_idx <= mk_current_word_idx + 1;
        end
      end else if (mk_state_d == MK_IDLE || mk_state_d == MK_EXECUTING) begin
        // Reset word index when idle or executing
        mk_current_word_idx <= '0;
      end
      
      // Latch configuration from SETUP
      if (issue_valid && issue_ready && opcode == ATT_DOT_SETUP) begin
        mk_latched_k <= registers[0][$clog2(MAX_K+1)-1:0];
        mk_latched_scale <= registers[1][15:0];
        mk_latched_shift <= registers[0][11:8];
        mk_k_words <= ((registers[0][$clog2(MAX_K+1)-1:0] + (WORD_ELEMS-1)) / WORD_ELEMS);
        // Clip defaults (could be extended to come from instruction)
        mk_latched_clip_min <= -32'sd32768;
        mk_latched_clip_max <= 32'sd32767;
      end
      
      // Latch scale/clip enables from RUN instructions  
      if ((mk_state_q == MK_IDLE || mk_state_q == MK_STAGING) && 
          issue_valid && issue_ready && 
          opcode inside {ATT_DOT_RUN, ATT_DOT_RUN_SCALE, ATT_DOT_RUN_CLIP}) begin
        mk_latched_en_scale <= (opcode == ATT_DOT_RUN_SCALE || opcode == ATT_DOT_RUN_CLIP);
        mk_latched_en_clip <= (opcode == ATT_DOT_RUN_CLIP);
      end
      
      // Update clip settings (could be extended to come from SETUP)
      mk_cfg_clip_min <= -32'sd32768;
      mk_cfg_clip_max <= 32'sd32767;
    end
  end

  // Result mux: select between regular MAC unit and microkernel engine
  always_comb begin
    if (use_microkernel && mk_result_valid) begin
      cvxif_resp_o.result_valid = mk_result_valid;
      cvxif_resp_o.result.hartid = issue_hartid;
      cvxif_resp_o.result.id = issue_id;
      cvxif_resp_o.result.data = mk_result;
      cvxif_resp_o.result.rd = issue_rd;
      cvxif_resp_o.result.we = 1'b1;
    end else begin
      cvxif_resp_o.result_valid  = result_valid && !use_microkernel;
      cvxif_resp_o.result.hartid = hartid;
      cvxif_resp_o.result.id     = id;
      cvxif_resp_o.result.data   = result;
      cvxif_resp_o.result.rd     = rd;
      cvxif_resp_o.result.we     = we && !use_microkernel;
    end
    // Note: overflow flag not part of standard CVXIF result
    // Could be exposed via custom CSR or debug interface in future
  end
  
  // Assertions for top-level verification
  `ifndef SYNTHESIS
  // Check CVXIF protocol compliance
  property p_issue_accept_implies_ready;
    @(posedge clk_i) disable iff (!rst_ni)
    (issue_resp.accept |-> issue_ready);
  endproperty
  assert property (p_issue_accept_implies_ready) 
    else $error("Accepted instruction but not ready");
  
  // Coverage: Track overflow events for debug
  cover property (@(posedge clk_i) overflow);
  `endif

endmodule
