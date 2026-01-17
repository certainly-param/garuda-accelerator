// Instruction Buffer - Queues instructions for parallel issue
// Phase 1.2 of Production Roadmap: Multi-Instruction Issue
// FIFO buffer for VLIW-style instruction packing

module instruction_buffer #(
    parameter int unsigned DEPTH        = 16,  // Buffer depth (entries)
    parameter int unsigned ISSUE_WIDTH  = 4,   // Instructions to issue per cycle (4-8)
    parameter int unsigned INSTR_WIDTH  = 32   // Instruction width (32 bits for RISC-V)
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,
    
    // Instruction input (from CPU via CVXIF)
    input  logic                        instr_valid_i,
    input  logic [INSTR_WIDTH-1:0]      instr_i,
    input  logic [4:0]                  rs1_addr_i,
    input  logic [4:0]                  rs2_addr_i,
    input  logic [4:0]                  rd_addr_i,
    output logic                        instr_ready_o,
    
    // Parallel instruction output (to issue stage)
    output logic                        issue_valid_o,
    output logic [ISSUE_WIDTH-1:0]      issue_mask_o,  // Which slots are valid
    output logic [ISSUE_WIDTH-1:0][INSTR_WIDTH-1:0] issue_instr_o,
    output logic [ISSUE_WIDTH-1:0][4:0] issue_rs1_addr_o,
    output logic [ISSUE_WIDTH-1:0][4:0] issue_rs2_addr_o,
    output logic [ISSUE_WIDTH-1:0][4:0] issue_rd_addr_o,
    input  logic                        issue_ready_i,  // Issue stage ready
    
    // Status
    output logic                        full_o,
    output logic                        empty_o,
    output logic [$clog2(DEPTH):0]      count_o
);

  // Instruction entry structure
  typedef struct packed {
    logic [INSTR_WIDTH-1:0] instr;
    logic [4:0]             rs1_addr;
    logic [4:0]             rs2_addr;
    logic [4:0]             rd_addr;
    logic                   valid;
  } instr_entry_t;
  
  // Instruction buffer (circular FIFO)
  instr_entry_t buffer [DEPTH];
  logic [$clog2(DEPTH)-1:0] wr_ptr_q, wr_ptr_d;
  logic [$clog2(DEPTH)-1:0] rd_ptr_q, rd_ptr_d;
  logic [$clog2(DEPTH):0]   count_q, count_d;
  
  // Issue packing: Pack up to ISSUE_WIDTH instructions for parallel issue
  logic [ISSUE_WIDTH-1:0]                can_issue;
  logic [$clog2(DEPTH)-1:0]              issue_ptrs [ISSUE_WIDTH];
  
  // Compute how many instructions can be issued
  always_comb begin
    int unsigned issue_count;
    issue_count = (count_q >= ISSUE_WIDTH) ? ISSUE_WIDTH : count_q[$clog2(DEPTH)-1:0];
    
    can_issue = '0;
    for (int i = 0; i < ISSUE_WIDTH; i++) begin
      if (i < issue_count) begin
        can_issue[i] = 1'b1;
        issue_ptrs[i] = (rd_ptr_q + i) % DEPTH;
      end else begin
        can_issue[i] = 1'b0;
        issue_ptrs[i] = '0;
      end
    end
  end
  
  // Issue instruction packing
  always_comb begin
    issue_valid_o = (count_q > 0) && issue_ready_i;
    issue_mask_o = can_issue;
    
    for (int i = 0; i < ISSUE_WIDTH; i++) begin
      if (can_issue[i] && buffer[issue_ptrs[i]].valid) begin
        issue_instr_o[i] = buffer[issue_ptrs[i]].instr;
        issue_rs1_addr_o[i] = buffer[issue_ptrs[i]].rs1_addr;
        issue_rs2_addr_o[i] = buffer[issue_ptrs[i]].rs2_addr;
        issue_rd_addr_o[i] = buffer[issue_ptrs[i]].rd_addr;
      end else begin
        issue_instr_o[i] = '0;
        issue_rs1_addr_o[i] = '0;
        issue_rs2_addr_o[i] = '0;
        issue_rd_addr_o[i] = '0;
      end
    end
  end
  
  // Write pointer update
  always_comb begin
    wr_ptr_d = wr_ptr_q;
    count_d = count_q;
    instr_ready_o = (count_q < DEPTH);
    
    if (instr_valid_i && (count_q < DEPTH)) begin
      wr_ptr_d = (wr_ptr_q + 1) % DEPTH;
      count_d = count_q + 1;
    end
  end
  
  // Read pointer update (on issue)
  always_comb begin
    rd_ptr_d = rd_ptr_q;
    count_d = count_q;
    
    if (issue_valid_o && issue_ready_i) begin
      int unsigned issue_count;
      issue_count = (count_q >= ISSUE_WIDTH) ? ISSUE_WIDTH : count_q[$clog2(DEPTH)-1:0];
      rd_ptr_d = (rd_ptr_q + issue_count) % DEPTH;
      count_d = count_q - issue_count;
    end
  end
  
  assign full_o = (count_q == DEPTH);
  assign empty_o = (count_q == 0);
  assign count_o = count_q;
  
  // Sequential logic
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int i = 0; i < DEPTH; i++) begin
        buffer[i] <= '0;
      end
      wr_ptr_q <= '0;
      rd_ptr_q <= '0;
      count_q <= '0;
    end else begin
      // Write new instruction
      if (instr_valid_i && (count_q < DEPTH)) begin
        buffer[wr_ptr_q].instr <= instr_i;
        buffer[wr_ptr_q].rs1_addr <= rs1_addr_i;
        buffer[wr_ptr_q].rs2_addr <= rs2_addr_i;
        buffer[wr_ptr_q].rd_addr <= rd_addr_i;
        buffer[wr_ptr_q].valid <= 1'b1;
      end
      
      // Invalidate issued instructions
      if (issue_valid_o && issue_ready_i) begin
        int unsigned issue_count;
        issue_count = (count_q >= ISSUE_WIDTH) ? ISSUE_WIDTH : count_q[$clog2(DEPTH)-1:0];
        for (int i = 0; i < issue_count; i++) begin
          buffer[(rd_ptr_q + i) % DEPTH].valid <= 1'b0;
        end
      end
      
      wr_ptr_q <= wr_ptr_d;
      rd_ptr_q <= rd_ptr_d;
      count_q <= count_d;
    end
  end

endmodule
