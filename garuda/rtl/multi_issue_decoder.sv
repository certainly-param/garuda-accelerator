// Multi-Issue Decoder - Decodes multiple instructions in parallel
// Phase 1.2 of Production Roadmap: Multi-Instruction Issue
// VLIW-style decoder for 4-8 instructions per cycle

module multi_issue_decoder #(
    parameter  type               copro_issue_resp_t          = logic,
    parameter  type               opcode_t                    = logic,
    parameter  int                NbInstr                     = 7,
    parameter  copro_issue_resp_t CoproInstr        [NbInstr] = {0},
    parameter  int unsigned       ISSUE_WIDTH                 = 4,   // Instructions per cycle (4-8)
    parameter  int unsigned       NrRgprPorts                 = 2,
    parameter  type               hartid_t                    = logic,
    parameter  type               id_t                        = logic,
    parameter  type               x_issue_req_t               = logic,
    parameter  type               x_issue_resp_t              = logic,
    parameter  type               x_register_t                = logic,
    parameter  type               registers_t                 = logic
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,
    
    // Parallel instruction input (from instruction buffer)
    input  logic                        issue_valid_i,
    input  logic [ISSUE_WIDTH-1:0]      issue_mask_i,  // Which slots are valid
    input  logic [ISSUE_WIDTH-1:0][31:0] issue_instr_i,
    output logic                        issue_ready_o,
    
    // Register read interface (from CPU)
    input  logic                        register_valid_i,
    input  x_register_t                 register_i [ISSUE_WIDTH],  // Parallel register read
    
    // Parallel decoder outputs (one per execution lane)
    output logic [ISSUE_WIDTH-1:0]      lane_valid_o,
    output registers_t                  registers_o [ISSUE_WIDTH],
    output opcode_t                     opcode_o [ISSUE_WIDTH],
    output hartid_t                     hartid_o [ISSUE_WIDTH],
    output id_t                         id_o [ISSUE_WIDTH],
    output logic [ISSUE_WIDTH-1:0][4:0] rd_o,
    output x_issue_resp_t               issue_resp_o [ISSUE_WIDTH],
    
    // Dependency checking
    output logic                        hazard_detected_o  // Register dependency hazard
);

  // Per-lane signals
  logic [ISSUE_WIDTH-1:0]      lane_issue_valid;
  logic [ISSUE_WIDTH-1:0]      lane_issue_ready;
  x_issue_resp_t                lane_issue_resp [ISSUE_WIDTH];
  
  // Decoder logic (parallel for all lanes)
  always_comb begin
    for (int i = 0; i < ISSUE_WIDTH; i++) begin
      lane_issue_valid[i] = issue_valid_i && issue_mask_i[i];
      lane_issue_ready[i] = 1'b1;
      lane_issue_resp[i].accept = 1'b0;
      lane_issue_resp[i].writeback = 1'b0;
      lane_issue_resp[i].register_read = '0;
      
      if (lane_issue_valid[i]) begin
        // Check against instruction patterns
        for (int j = 0; j < NbInstr; j++) begin
          if (((CoproInstr[j].mask & issue_instr_i[i]) == CoproInstr[j].instr)) begin
            lane_issue_resp[i].accept = CoproInstr[j].resp.accept;
            lane_issue_resp[i].writeback = CoproInstr[j].resp.writeback;
            lane_issue_resp[i].register_read = CoproInstr[j].resp.register_read;
          end
        end
      end
      
      // Extract operands
      registers_o[i] = '0;
      for (int j = 0; j < NrRgprPorts; j++) begin
        registers_o[i][j] = register_i[i].rs[j];
      end
      
      // Extract opcode and addresses
      // Simplified: extract from instruction format (would use proper decoder)
      rd_o[i] = issue_instr_i[i][11:7];
      hartid_o[i] = hartid_t'(0);
      id_o[i] = id_t'(i);  // Use lane index as ID
      opcode_o[i] = opcode_t'(issue_instr_i[i][6:2]);  // Simplified opcode extraction
      
      lane_valid_o[i] = lane_issue_valid[i] && lane_issue_resp[i].accept && lane_issue_ready[i];
      issue_resp_o[i] = lane_issue_resp[i];
    end
  end
  
  // Hazard detection: Check for register dependencies between lanes
  // RAW (Read After Write) hazard: Lane i writes to rd, lane j > i reads from same rd
  logic [ISSUE_WIDTH-1:0][ISSUE_WIDTH-1:0] hazard_matrix;
  
  always_comb begin
    hazard_detected_o = 1'b0;
    
    for (int i = 0; i < ISSUE_WIDTH; i++) begin
      for (int j = i + 1; j < ISSUE_WIDTH; j++) begin
        // Check if lane i writes and lane j reads the same register
        if (issue_mask_i[i] && issue_mask_i[j] && 
            issue_resp_o[i].writeback && 
            issue_resp_o[j].register_read[0] &&  // Lane j reads rs1
            (rd_o[i] != 0) &&  // Not x0
            (rd_o[i] == issue_instr_i[j][19:15])) begin  // rs1 matches rd
          hazard_detected_o = 1'b1;
        end
        
        if (issue_mask_i[i] && issue_mask_i[j] && 
            issue_resp_o[i].writeback && 
            issue_resp_o[j].register_read[1] &&  // Lane j reads rs2
            (rd_o[i] != 0) &&  // Not x0
            (rd_o[i] == issue_instr_i[j][24:20])) begin  // rs2 matches rd
          hazard_detected_o = 1'b1;
        end
      end
    end
  end
  
  // Issue ready: All enabled lanes must be ready, and no hazards
  always_comb begin
    issue_ready_o = 1'b1;
    
    for (int i = 0; i < ISSUE_WIDTH; i++) begin
      if (issue_mask_i[i]) begin
        // Check if this lane's decoder is ready
        // (simplified: assume ready if no hazard)
        if (hazard_detected_o) begin
          issue_ready_o = 1'b0;
        end
      end
    end
  end

endmodule
