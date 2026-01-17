// Testbench for Register Rename Table
// Tests rename table, free list, and commit queue functionality

`timescale 1ns / 1ps

module tb_register_rename_table;

  parameter int unsigned ARCH_REGS    = 32;
  parameter int unsigned PHYS_REGS    = 64;
  parameter int unsigned ISSUE_WIDTH  = 4;
  parameter int unsigned XLEN         = 32;

  logic clk, rst_n;
  
  // Rename interface
  logic [ISSUE_WIDTH-1:0] rename_valid_i;
  logic [ISSUE_WIDTH*5-1:0] arch_rs1_i;
  logic [ISSUE_WIDTH*5-1:0] arch_rs2_i;
  logic [ISSUE_WIDTH*5-1:0] arch_rd_i;
  logic [ISSUE_WIDTH-1:0] rename_ready_o;
  logic [ISSUE_WIDTH*$clog2(PHYS_REGS)-1:0] phys_rs1_o;
  logic [ISSUE_WIDTH*$clog2(PHYS_REGS)-1:0] phys_rs2_o;
  logic [ISSUE_WIDTH*$clog2(PHYS_REGS)-1:0] phys_rd_o;
  logic [ISSUE_WIDTH*$clog2(PHYS_REGS)-1:0] old_phys_rd_o;
  
  // Commit interface
  logic [ISSUE_WIDTH-1:0] commit_valid_i;
  logic [ISSUE_WIDTH*$clog2(PHYS_REGS)-1:0] commit_phys_rd_i;
  logic commit_ready_o;
  
  // Free list status
  logic free_list_empty_o;
  logic [$clog2(PHYS_REGS):0] free_count_o;
  
  // Clock generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk;  // 10ns period = 100MHz
  end
  
  // Reset generation
  initial begin
    rst_n = 0;
    #50;
    rst_n = 1;
  end
  
  // Instantiate DUT
  register_rename_table #(
      .ARCH_REGS(ARCH_REGS),
      .PHYS_REGS(PHYS_REGS),
      .XLEN(XLEN),
      .ISSUE_WIDTH(ISSUE_WIDTH)
  ) dut (
      .clk_i(clk),
      .rst_ni(rst_n),
      .rename_valid_i(rename_valid_i),
      .arch_rs1_i(arch_rs1_i),
      .arch_rs2_i(arch_rs2_i),
      .arch_rd_i(arch_rd_i),
      .rename_ready_o(rename_ready_o),
      .phys_rs1_o(phys_rs1_o),
      .phys_rs2_o(phys_rs2_o),
      .phys_rd_o(phys_rd_o),
      .old_phys_rd_o(old_phys_rd_o),
      .commit_valid_i(commit_valid_i),
      .commit_phys_rd_i(commit_phys_rd_i),
      .commit_ready_o(commit_ready_o),
      .free_list_empty_o(free_list_empty_o),
      .free_count_o(free_count_o)
  );
  
  // Test stimulus
  int test_count = 0;
  int pass_count = 0;
  int fail_count = 0;
  logic [$clog2(PHYS_REGS):0] free_count_before;
  int renames;
  logic [$clog2(PHYS_REGS)-1:0] saved_old_p5;
  logic [$clog2(PHYS_REGS):0] start_free;
  
  task check_result(int test_num, string test_name, logic result, logic expected);
    test_count++;
    if (result == expected) begin
      pass_count++;
      $display("[TEST %0d] %s: PASS", test_num, test_name);
    end else begin
      fail_count++;
      $display("[TEST %0d] %s: FAIL (got %b, expected %b)", test_num, test_name, result, expected);
    end
  endtask
  
  initial begin
    $display("========================================");
    $display("Register Rename Table Testbench");
    $display("Arch: %0d regs, Phys: %0d regs, Issue: %0d-wide", ARCH_REGS, PHYS_REGS, ISSUE_WIDTH);
    $display("========================================\n");
    
    // Initialize
    rename_valid_i = '0;
    arch_rs1_i = '0;
    arch_rs2_i = '0;
    arch_rd_i  = '0;
    commit_valid_i = '0;
    commit_phys_rd_i = '0;
    
    @(posedge rst_n);
    #20;
    
    // Test 1: Initial state - free list should have 32 free registers
    $display("\n[TEST 1] Initial free list count");
    check_result(1, "Free count == 32", free_count_o == (PHYS_REGS - ARCH_REGS), 1'b1);
    check_result(1, "Free list not empty", free_list_empty_o == 1'b0, 1'b1);
    
    // Test 2: Rename single instruction (rd = x5, rs1 = x3, rs2 = x4)
    $display("\n[TEST 2] Single instruction rename");
    rename_valid_i[0] = 1'b1;
    arch_rs1_i[0*5 +: 5] = 5'd3;  // x3
    arch_rs2_i[0*5 +: 5] = 5'd4;  // x4
    arch_rd_i[0*5 +: 5]  = 5'd5;  // x5 (destination)
    @(posedge clk);
    
    if (rename_ready_o[0]) begin
      check_result(2, "Rename ready", 1'b1, 1'b1);
      check_result(2, "Physical rs1 is x3", phys_rs1_o[0*$clog2(PHYS_REGS) +: $clog2(PHYS_REGS)] == 5'd3, 1'b1);
      check_result(2, "Physical rs2 is x4", phys_rs2_o[0*$clog2(PHYS_REGS) +: $clog2(PHYS_REGS)] == 5'd4, 1'b1);
      check_result(2, "Physical rd allocated", phys_rd_o[0*$clog2(PHYS_REGS) +: $clog2(PHYS_REGS)] >= ARCH_REGS, 1'b1);
      check_result(2, "Old physical rd is x5", old_phys_rd_o[0*$clog2(PHYS_REGS) +: $clog2(PHYS_REGS)] == 5'd5, 1'b1);
      $display("    Allocated phys_rd[0] = %0d (should be >= %0d)", phys_rd_o[0*$clog2(PHYS_REGS) +: $clog2(PHYS_REGS)], ARCH_REGS);
      $display("    Old phys_rd[0] = %0d (should be %0d)", old_phys_rd_o[0*$clog2(PHYS_REGS) +: $clog2(PHYS_REGS)], 5'd5);
      // Save for later commit test (TB must not rely on DUT holding this)
      saved_old_p5 = old_phys_rd_o[0*$clog2(PHYS_REGS) +: $clog2(PHYS_REGS)];
    end else begin
      check_result(2, "Rename ready", 1'b0, 1'b1);
    end
    
    rename_valid_i[0] = 1'b0;
    @(posedge clk);
    
    // Test 3: Check free list count after rename
    $display("\n[TEST 3] Free list after rename");
    check_result(3, "Free count decreased", free_count_o == (PHYS_REGS - ARCH_REGS - 1), 1'b1);
    
    // Test 4: Rename multiple instructions in parallel
    $display("\n[TEST 4] Parallel rename (4 instructions)");
    rename_valid_i = 4'b1111;
    arch_rd_i[0*5 +: 5] = 5'd10;  // x10 → new physical
    arch_rd_i[1*5 +: 5] = 5'd11;  // x11 → new physical
    arch_rd_i[2*5 +: 5] = 5'd12;  // x12 → new physical
    arch_rd_i[3*5 +: 5] = 5'd13;  // x13 → new physical
    arch_rs1_i[0*5 +: 5] = 5'd1;
    arch_rs1_i[1*5 +: 5] = 5'd2;
    arch_rs1_i[2*5 +: 5] = 5'd3;
    arch_rs1_i[3*5 +: 5] = 5'd4;
    arch_rs2_i = '0;
    
    @(posedge clk);
    
    if (rename_ready_o == 4'b1111) begin
      check_result(4, "All renames ready", 1'b1, 1'b1);
      $display("    phys_rd[0] = %0d (x10)", phys_rd_o[0*$clog2(PHYS_REGS) +: $clog2(PHYS_REGS)]);
      $display("    phys_rd[1] = %0d (x11)", phys_rd_o[1*$clog2(PHYS_REGS) +: $clog2(PHYS_REGS)]);
      $display("    phys_rd[2] = %0d (x12)", phys_rd_o[2*$clog2(PHYS_REGS) +: $clog2(PHYS_REGS)]);
      $display("    phys_rd[3] = %0d (x13)", phys_rd_o[3*$clog2(PHYS_REGS) +: $clog2(PHYS_REGS)]);
      // Check all physical registers are different
      check_result(4, "Unique physical regs", 
                   (phys_rd_o[0*$clog2(PHYS_REGS) +: $clog2(PHYS_REGS)] != phys_rd_o[1*$clog2(PHYS_REGS) +: $clog2(PHYS_REGS)]) &&
                   (phys_rd_o[1*$clog2(PHYS_REGS) +: $clog2(PHYS_REGS)] != phys_rd_o[2*$clog2(PHYS_REGS) +: $clog2(PHYS_REGS)]) &&
                   (phys_rd_o[2*$clog2(PHYS_REGS) +: $clog2(PHYS_REGS)] != phys_rd_o[3*$clog2(PHYS_REGS) +: $clog2(PHYS_REGS)]), 1'b1);
    end
    
    rename_valid_i = '0;
    @(posedge clk);
    
    // Test 5: Test false dependency removal
    $display("\n[TEST 5] False dependency removal");
    // Instruction 1: mul x5, x1, x2 (writes x5)
    rename_valid_i[0] = 1'b1;
    arch_rs1_i[0*5 +: 5] = 5'd1;
    arch_rs2_i[0*5 +: 5] = 5'd2;
    arch_rd_i[0*5 +: 5]  = 5'd5;
    
    // Instruction 2: add x6, x5, x3 (reads x5 - should get old physical)
    rename_valid_i[1] = 1'b1;
    arch_rs1_i[1*5 +: 5] = 5'd5;  // Reads x5 (should get old physical, not new!)
    arch_rs2_i[1*5 +: 5] = 5'd3;
    arch_rd_i[1*5 +: 5]  = 5'd6;
    
    @(posedge clk);
    
    if (rename_ready_o[0] && rename_ready_o[1]) begin
      // x5 should map to old physical register (before rename) for instruction 1
      // But instruction 2 reading x5 should get the OLD value
      // Instruction 1's new write to x5 gets a NEW physical register
      check_result(5, "Both renames ready", 1'b1, 1'b1);
      $display("    Instr 0: x5 → phys_rd[0] = %0d (new)", phys_rd_o[0*$clog2(PHYS_REGS) +: $clog2(PHYS_REGS)]);
      $display("    Instr 1: x5 → phys_rs1[1] = %0d (old, not %0d)",
               phys_rs1_o[1*$clog2(PHYS_REGS) +: $clog2(PHYS_REGS)],
               phys_rd_o[0*$clog2(PHYS_REGS) +: $clog2(PHYS_REGS)]);
      check_result(5, "False dep removed",
                   phys_rs1_o[1*$clog2(PHYS_REGS) +: $clog2(PHYS_REGS)] != phys_rd_o[0*$clog2(PHYS_REGS) +: $clog2(PHYS_REGS)], 1'b1);
    end
    
    rename_valid_i = '0;
    @(posedge clk);
    
    // Test 6: Commit operation (return physical register to free list)
    $display("\n[TEST 6] Commit operation");
    free_count_before = free_count_o;
    
    // Commit the first instruction (rd = x5)
    commit_valid_i[0] = 1'b1;
    commit_phys_rd_i[0*$clog2(PHYS_REGS) +: $clog2(PHYS_REGS)] =
        saved_old_p5;  // Commit old physical reg saved from Test 2
    @(posedge clk);
    commit_valid_i[0] = 1'b0;
    commit_phys_rd_i = '0;
    
    // Wait a few cycles for commit to process
    @(posedge clk);
    @(posedge clk);
    
    check_result(6, "Free count increased", free_count_o == (free_count_before + 1), 1'b1);
    
    // Test 7: Rename x0 (should always map to physical 0)
    $display("\n[TEST 7] x0 always maps to p0");
    rename_valid_i[0] = 1'b1;
    arch_rs1_i[0*5 +: 5] = 5'd0;  // x0
    arch_rs2_i[0*5 +: 5] = 5'd1;
    arch_rd_i[0*5 +: 5]  = 5'd0;  // x0 (destination - should not rename!)
    
    @(posedge clk);
    
    if (rename_ready_o[0]) begin
      check_result(7, "x0 rs1 maps to p0",
                   phys_rs1_o[0*$clog2(PHYS_REGS) +: $clog2(PHYS_REGS)] == 0, 1'b1);
      // x0 as destination should still map to 0 (or not allocate new physical reg)
      $display("    x0 as rd: phys_rd[0] = %0d", phys_rd_o[0*$clog2(PHYS_REGS) +: $clog2(PHYS_REGS)]);
    end
    
    rename_valid_i = '0;
    @(posedge clk);
    
    // Test 8: Free list exhaustion (rename many registers)
    $display("\n[TEST 8] Free list exhaustion test");
    renames = 0;
    start_free = free_count_o;
    
    // Rename until free list is empty (should stop when free regs are exhausted)
    for (int i = 0; i < (start_free + 5); i++) begin
      rename_valid_i[0] = 1'b1;
      arch_rd_i[0*5 +: 5]  = (15 + (i % 16));  // Use x15-x30
      arch_rs1_i[0*5 +: 5] = 5'd1;
      arch_rs2_i[0*5 +: 5] = 5'd2;
      
      @(posedge clk);
      
      if (rename_ready_o[0]) begin
        renames++;
      end
      
      rename_valid_i[0] = 1'b0;
      @(posedge clk);
    end
    
    check_result(8, "Renames before exhaustion", renames == start_free, 1'b1);
    check_result(8, "Free list empty", free_list_empty_o == 1'b1, 1'b1);
    
    #100;
    
    // Summary
    $display("\n========================================");
    $display("Test Summary");
    $display("Total tests: %0d", test_count);
    $display("Passed: %0d", pass_count);
    $display("Failed: %0d", fail_count);
    if (fail_count == 0) begin
      $display("ALL TESTS PASSED!");
    end else begin
      $display("SOME TESTS FAILED!");
    end
    $display("========================================\n");
    
    #100;
    $finish;
  end

endmodule
