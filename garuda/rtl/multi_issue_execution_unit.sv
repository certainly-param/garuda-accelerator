// Multi-Issue Execution Unit - Executes multiple instructions in parallel
// Phase 1.2 of Production Roadmap: Multi-Instruction Issue
// Multiple execution lanes for parallel instruction execution

module multi_issue_execution_unit #(
    parameter int unsigned ISSUE_WIDTH  = 4,   // Number of execution lanes (4-8)
    parameter int unsigned XLEN         = 32,
    parameter int unsigned NUM_LANES    = 16,
    parameter int unsigned LANE_WIDTH   = 32,
    parameter type         opcode_t     = logic,
    parameter type         hartid_t     = logic,
    parameter type         id_t         = logic
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,
    
    // Parallel instruction inputs (from multi-issue decoder)
    input  logic [ISSUE_WIDTH-1:0]      lane_valid_i,
    input  logic [ISSUE_WIDTH-1:0][XLEN-1:0] rs1_i,
    input  logic [ISSUE_WIDTH-1:0][XLEN-1:0] rs2_i,
    input  logic [ISSUE_WIDTH-1:0][XLEN-1:0] rd_i,
    input  opcode_t                     opcode_i [ISSUE_WIDTH],
    input  hartid_t                     hartid_i [ISSUE_WIDTH],
    input  id_t                         id_i [ISSUE_WIDTH],
    input  logic [ISSUE_WIDTH-1:0][4:0] rd_addr_i,
    
    // Parallel results outputs
    output logic [ISSUE_WIDTH-1:0]      result_valid_o,
    output logic [ISSUE_WIDTH-1:0][XLEN-1:0] result_o,
    output logic [ISSUE_WIDTH-1:0]      result_we_o,
    output logic [ISSUE_WIDTH-1:0][4:0] result_rd_addr_o,
    output hartid_t                     result_hartid_o [ISSUE_WIDTH],
    output id_t                         result_id_o [ISSUE_WIDTH],
    output logic [ISSUE_WIDTH-1:0]      result_overflow_o
);

  // Instantiate ISSUE_WIDTH execution units (one per lane)
  // For now, use multi-lane wrapper for each lane (could be optimized)
  for (genvar i = 0; i < ISSUE_WIDTH; i++) begin : gen_exec_units
    // Each execution lane gets its own MAC unit
    // For multi-lane operations, use multi-lane unit
    // For scalar operations, use scalar unit
    
    // Simplified: Use multi-lane wrapper for all (can be optimized)
    int8_mac_multilane_wrapper #(
        .XLEN(XLEN),
        .NUM_LANES(NUM_LANES),
        .LANE_WIDTH(LANE_WIDTH),
        .opcode_t(opcode_t),
        .hartid_t(hartid_t),
        .id_t(id_t)
    ) i_exec_unit (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .rs1_i(rs1_i[i]),
        .rs2_i(rs2_i[i]),
        .rd_i(rd_i[i]),
        .opcode_i(opcode_i[i]),
        .hartid_i(hartid_i[i]),
        .id_i(id_i[i]),
        .rd_addr_i(rd_addr_i[i]),
        .valid_i(lane_valid_i[i]),
        .lane_idx_i('0),  // Not used for multi-issue (each lane is independent)
        .lane_load_i(1'b0),
        .lane_exec_i(1'b0),
        .result_o(result_o[i]),
        .valid_o(result_valid_o[i]),
        .we_o(result_we_o[i]),
        .rd_addr_o(result_rd_addr_o[i]),
        .hartid_o(result_hartid_o[i]),
        .id_o(result_id_o[i]),
        .overflow_o(result_overflow_o[i])
    );
  end

endmodule
