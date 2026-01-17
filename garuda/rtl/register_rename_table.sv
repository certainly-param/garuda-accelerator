// Register Rename Table - Removes false dependencies in multi-issue
// Phase 1.2 Enhancement: Register Renaming
// Maps architectural registers to physical registers

module register_rename_table #(
    parameter int unsigned ARCH_REGS      = 32,   // Architectural registers (x0-x31)
    parameter int unsigned PHYS_REGS      = 64,   // Physical registers (rename pool)
    parameter int unsigned XLEN           = 32,   // Register width
    parameter int unsigned ISSUE_WIDTH    = 4     // Instructions per cycle
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,
    
    // Rename requests (parallel, one per instruction)
    input  logic [ISSUE_WIDTH-1:0]      rename_valid_i,
    input  logic [ISSUE_WIDTH*5-1:0]    arch_rs1_i,      // packed: lane0 in [4:0]
    input  logic [ISSUE_WIDTH*5-1:0]    arch_rs2_i,
    input  logic [ISSUE_WIDTH*5-1:0]    arch_rd_i,
    output logic [ISSUE_WIDTH-1:0]      rename_ready_o,
    output logic [ISSUE_WIDTH*$clog2(PHYS_REGS)-1:0] phys_rs1_o,  // packed
    output logic [ISSUE_WIDTH*$clog2(PHYS_REGS)-1:0] phys_rs2_o,
    output logic [ISSUE_WIDTH*$clog2(PHYS_REGS)-1:0] phys_rd_o,
    output logic [ISSUE_WIDTH*$clog2(PHYS_REGS)-1:0] old_phys_rd_o,
    
    // Commit interface (writeback completed instructions)
    input  logic [ISSUE_WIDTH-1:0]      commit_valid_i,
    input  logic [ISSUE_WIDTH*$clog2(PHYS_REGS)-1:0] commit_phys_rd_i,
    output logic                        commit_ready_o,
    
    // Free list management
    output logic                        free_list_empty_o,
    output logic [$clog2(PHYS_REGS):0]  free_count_o
);

  localparam int unsigned PHYS_IDX_W  = $clog2(PHYS_REGS);
  localparam int unsigned FL_DEPTH    = (PHYS_REGS - ARCH_REGS);
  localparam int unsigned FL_COUNT_W  = $clog2(FL_DEPTH + 1);

  // Unpacked per-lane views of packed buses (Icarus-friendly)
  logic [4:0]          arch_rs1_lane [0:ISSUE_WIDTH-1];
  logic [4:0]          arch_rs2_lane [0:ISSUE_WIDTH-1];
  logic [4:0]          arch_rd_lane  [0:ISSUE_WIDTH-1];
  logic [PHYS_IDX_W-1:0] commit_phys_rd_lane [0:ISSUE_WIDTH-1];

  logic [PHYS_IDX_W-1:0] phys_rs1_lane [0:ISSUE_WIDTH-1];
  logic [PHYS_IDX_W-1:0] phys_rs2_lane [0:ISSUE_WIDTH-1];
  logic [PHYS_IDX_W-1:0] phys_rd_lane  [0:ISSUE_WIDTH-1];
  logic [PHYS_IDX_W-1:0] old_phys_rd_lane [0:ISSUE_WIDTH-1];

  // Map packed buses <-> unpacked per-lane signals
  genvar g;
  generate
    for (g = 0; g < ISSUE_WIDTH; g = g + 1) begin : gen_lane_map
      assign arch_rs1_lane[g] = arch_rs1_i[g*5 +: 5];
      assign arch_rs2_lane[g] = arch_rs2_i[g*5 +: 5];
      assign arch_rd_lane[g]  = arch_rd_i[g*5 +: 5];

      assign commit_phys_rd_lane[g] = commit_phys_rd_i[g*PHYS_IDX_W +: PHYS_IDX_W];

      assign phys_rs1_o[g*PHYS_IDX_W +: PHYS_IDX_W]     = phys_rs1_lane[g];
      assign phys_rs2_o[g*PHYS_IDX_W +: PHYS_IDX_W]     = phys_rs2_lane[g];
      assign phys_rd_o[g*PHYS_IDX_W +: PHYS_IDX_W]      = phys_rd_lane[g];
      assign old_phys_rd_o[g*PHYS_IDX_W +: PHYS_IDX_W]  = old_phys_rd_lane[g];
    end
  endgenerate

  // Rename table: Maps architectural register → physical register
  logic [PHYS_IDX_W-1:0] rename_table [ARCH_REGS];

  // Free list: Available physical registers (stack-based for Icarus friendliness)
  logic [PHYS_IDX_W-1:0] free_list [FL_DEPTH];
  logic [FL_COUNT_W-1:0] free_list_count_q, free_list_count_d;

  // Allocation bookkeeping (per-issue lane)
  logic [ISSUE_WIDTH-1:0]               needs_alloc;
  logic [ISSUE_WIDTH-1:0]               can_allocate;
  logic [PHYS_IDX_W-1:0]               allocated_phys_rd [ISSUE_WIDTH];
  integer                               alloc_index [0:ISSUE_WIDTH-1];
  integer                               total_alloc;

  // Commit/free bookkeeping
  logic [ISSUE_WIDTH-1:0] free_en;
  integer                 total_free;
  integer                 free_offset;
  integer                 free_count_after_alloc;

  // Temporary integers (module-scope for older Icarus)
  integer                 next_count;
  // IMPORTANT: do not drive the same temp from multiple always blocks.
  integer                 free_count_int_can;
  integer                 free_count_int_alloc;

  // Dedicated loop indices (avoid "for (int i=...)" on older Icarus)
  integer i_alloc;
  integer i_can;
  integer i_alloc2;
  integer j_init;
  integer i_out;
  integer i_commit;
  integer i_reset;
  integer i_reset_fl;
  integer i_seq_rename;
  integer i_seq_free;

  // Compute which lanes need allocation and their allocation index (packed)
  always @(*) begin
    total_alloc = 0;
    for (i_alloc = 0; i_alloc < ISSUE_WIDTH; i_alloc = i_alloc + 1) begin
      needs_alloc[i_alloc]  = rename_valid_i[i_alloc] && (arch_rd_lane[i_alloc] != 5'd0);
      alloc_index[i_alloc]  = total_alloc;
      if (needs_alloc[i_alloc]) begin
        total_alloc++;
      end
    end
  end

  // Can we allocate for each lane?
  always @(*) begin
    free_count_int_can = free_list_count_q;
    for (i_can = 0; i_can < ISSUE_WIDTH; i_can = i_can + 1) begin
      if (!rename_valid_i[i_can]) begin
        can_allocate[i_can] = 1'b0;
      end else if (!needs_alloc[i_can]) begin
        // No destination (e.g. rd=x0) => does not require a free phys reg
        can_allocate[i_can] = 1'b1;
      end else begin
        can_allocate[i_can] = (free_count_int_can > alloc_index[i_can]);
      end
    end
  end

  // Allocate physical registers from free list (stack pop from the "top")
  always @(*) begin
    free_count_int_alloc = free_list_count_q;
    for (i_alloc2 = 0; i_alloc2 < ISSUE_WIDTH; i_alloc2 = i_alloc2 + 1) begin
      if (rename_valid_i[i_alloc2] && needs_alloc[i_alloc2] && can_allocate[i_alloc2]) begin
        // alloc_index[i] = 0 => pop last element, alloc_index[i] = 1 => pop second-last, etc.
        allocated_phys_rd[i_alloc2] = free_list[free_count_int_alloc - 1 - alloc_index[i_alloc2]];
      end else begin
        allocated_phys_rd[i_alloc2] = '0;
      end
    end
  end

  // Rename table lookup and outputs
  always @(*) begin
    rename_ready_o = '0;
    for (j_init = 0; j_init < ISSUE_WIDTH; j_init = j_init + 1) begin
      phys_rs1_lane[j_init]    = '0;
      phys_rs2_lane[j_init]    = '0;
      phys_rd_lane[j_init]     = '0;
      old_phys_rd_lane[j_init] = '0;
    end

    for (i_out = 0; i_out < ISSUE_WIDTH; i_out = i_out + 1) begin
      if (rename_valid_i[i_out] && can_allocate[i_out]) begin
        rename_ready_o[i_out] = 1'b1;

        // Lookup physical registers for sources (x0 always maps to p0)
        phys_rs1_lane[i_out] = (arch_rs1_lane[i_out] != 5'd0) ? rename_table[arch_rs1_lane[i_out]] : '0;
        phys_rs2_lane[i_out] = (arch_rs2_lane[i_out] != 5'd0) ? rename_table[arch_rs2_lane[i_out]] : '0;

        // Destination allocation (rd=x0 => no allocation)
        phys_rd_lane[i_out]     = needs_alloc[i_out] ? allocated_phys_rd[i_out] : '0;
        old_phys_rd_lane[i_out] = (arch_rd_lane[i_out] != 5'd0) ? rename_table[arch_rd_lane[i_out]] : '0;
      end
    end
  end

  // Commit/free list inputs (free phys regs returned by commit)
  always @(*) begin
    total_free = 0;
    for (i_commit = 0; i_commit < ISSUE_WIDTH; i_commit = i_commit + 1) begin
      // Never free p0; caller is responsible for correctness for other regs.
      free_en[i_commit] = commit_valid_i[i_commit] && (commit_phys_rd_lane[i_commit] != '0);
      if (free_en[i_commit]) begin
        total_free++;
      end
    end
  end

  // Free list pointer/count update
  always @(*) begin
    next_count = free_list_count_q - total_alloc + total_free;

    // Also compute where to start pushing freed regs after pops.
    free_count_after_alloc = free_list_count_q - total_alloc;
    if (free_count_after_alloc < 0) begin
      free_count_after_alloc = 0;
    end

    if (next_count < 0) begin
      free_list_count_d = '0;
    end else if (next_count > FL_DEPTH) begin
      free_list_count_d = FL_COUNT_W'(FL_DEPTH);
    end else begin
      free_list_count_d = FL_COUNT_W'(next_count);
    end
  end

  assign free_list_empty_o = (free_list_count_q == 0);
  assign free_count_o      = free_list_count_q;
  assign commit_ready_o    = 1'b1;  // Always ready for commit in this model

  // Sequential state updates
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      // Initialize rename table: arch reg i → phys reg i
      for (i_reset = 0; i_reset < ARCH_REGS; i_reset = i_reset + 1) begin
        // Avoid sized casts (older Icarus can mishandle them for arrays)
        rename_table[i_reset] <= i_reset;
      end

      // Initialize free list: phys regs ARCH_REGS to PHYS_REGS-1
      for (i_reset_fl = 0; i_reset_fl < FL_DEPTH; i_reset_fl = i_reset_fl + 1) begin
        free_list[i_reset_fl] <= (ARCH_REGS + i_reset_fl);
      end

      free_list_count_q <= FL_COUNT_W'(FL_DEPTH);
    end else begin
      // Update rename table (on successful rename with destination)
      for (i_seq_rename = 0; i_seq_rename < ISSUE_WIDTH; i_seq_rename = i_seq_rename + 1) begin
        if (rename_valid_i[i_seq_rename] && needs_alloc[i_seq_rename] && can_allocate[i_seq_rename]) begin
          rename_table[arch_rd_lane[i_seq_rename]] <= allocated_phys_rd[i_seq_rename];
        end
      end

      // Write freed phys regs into the free list (stack push after pops)
      free_offset = 0;
      for (i_seq_free = 0; i_seq_free < ISSUE_WIDTH; i_seq_free = i_seq_free + 1) begin
        if (free_en[i_seq_free]) begin
          // Push at the current top (after this cycle's pops)
          free_list[free_count_after_alloc + free_offset] <= commit_phys_rd_lane[i_seq_free];
          free_offset++;
        end
      end

      // Update free list count
      free_list_count_q <= free_list_count_d;
    end
  end

endmodule
