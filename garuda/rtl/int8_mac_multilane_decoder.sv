// Enhanced Decoder for Multi-Lane MAC Operations
// Extends base decoder with lane control signal extraction

module int8_mac_multilane_decoder #(
    parameter  type               copro_issue_resp_t          = logic,
    parameter  type               opcode_t                    = logic,
    parameter  int                NbInstr                     = 1,
    parameter  copro_issue_resp_t CoproInstr        [NbInstr] = {0},
    parameter  int unsigned       NrRgprPorts                 = 2,
    parameter  type               hartid_t                    = logic,
    parameter  type               id_t                        = logic,
    parameter  type               x_issue_req_t               = logic,
    parameter  type               x_issue_resp_t              = logic,
    parameter  type               x_register_t                = logic,
    parameter  type               registers_t                 = logic
) (
    input  logic            clk_i,
    input  logic            rst_ni,
    
    input  logic            issue_valid_i,
    input  x_issue_req_t    issue_req_i,
    output logic            issue_ready_o,
    output x_issue_resp_t   issue_resp_o,
    
    input  logic            register_valid_i,
    input  x_register_t     register_i,
    
    output registers_t      registers_o,
    output opcode_t         opcode_o,
    output hartid_t         hartid_o,
    output id_t             id_o,
    output logic [4:0]      rd_o,
    
    // Multi-lane control signals
    output logic [3:0]      lane_idx_o,      // Lane index for SIMD_DOT_LOAD
    output logic            lane_load_o,     // Load signal for SIMD_DOT_LOAD
    output logic            lane_exec_o      // Execute signal for SIMD_DOT_EXEC
);

  // Use base decoder
  logic            base_issue_ready;
  x_issue_resp_t   base_issue_resp;
  registers_t      base_registers;
  opcode_t         base_opcode;
  hartid_t         base_hartid;
  id_t             base_id;
  logic [4:0]      base_rd;

  int8_mac_decoder #(
      .copro_issue_resp_t(copro_issue_resp_t),
      .opcode_t(opcode_t),
      .NbInstr(NbInstr),
      .CoproInstr(CoproInstr),
      .NrRgprPorts(NrRgprPorts),
      .hartid_t(hartid_t),
      .id_t(id_t),
      .x_issue_req_t(x_issue_req_t),
      .x_issue_resp_t(x_issue_resp_t),
      .x_register_t(x_register_t),
      .registers_t(registers_t)
  ) i_base_decoder (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .issue_valid_i(issue_valid_i),
      .issue_req_i(issue_req_i),
      .issue_ready_o(base_issue_ready),
      .issue_resp_o(base_issue_resp),
      .register_valid_i(register_valid_i),
      .register_i(register_i),
      .registers_o(base_registers),
      .opcode_o(base_opcode),
      .hartid_o(base_hartid),
      .id_o(base_id),
      .rd_o(base_rd)
  );
  
  // Pass through base decoder outputs
  assign issue_ready_o = base_issue_ready;
  assign issue_resp_o = base_issue_resp;
  assign registers_o = base_registers;
  assign opcode_o = base_opcode;
  assign hartid_o = base_hartid;
  assign id_o = base_id;
  assign rd_o = base_rd;
  
  // Extract lane control signals from instruction
  // For SIMD_DOT_LOAD: lane index is in imm[3:0] = instr[11:8]
  // For SIMD_DOT_EXEC: set exec signal
  always_comb begin
    lane_idx_o = '0;
    lane_load_o = 1'b0;
    lane_exec_o = 1'b0;
    
    if (issue_valid_i && base_issue_resp.accept) begin
      case (base_opcode)
        // SIMD_DOT_LOAD: Extract lane index from instruction bits [11:8]
        // RISC-V instruction format: imm[11:0] in bits [31:20]
        // For custom instructions, we use bits [11:8] for lane index
        // Note: SIMD_DOT_LOAD = 4'b0110 = 6
        opcode_t'(6): begin  // SIMD_DOT_LOAD
          lane_idx_o = issue_req_i.instr[11:8];  // Extract lane index from imm[3:0]
          lane_load_o = 1'b1;
        end
        
        // SIMD_DOT_EXEC: Execute multi-lane operation
        // Note: SIMD_DOT_EXEC = 4'b0111 = 7
        opcode_t'(7): begin  // SIMD_DOT_EXEC
          lane_exec_o = 1'b1;
        end
        
        default: begin
          // Default: no multi-lane control for other opcodes
        end
      endcase
    end
  end

endmodule
