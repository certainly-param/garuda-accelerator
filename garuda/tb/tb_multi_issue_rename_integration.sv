// Integration testbench: multi-issue style rename + stall/commit handshake
// Demonstrates:
// - Free-list exhaustion backpressure (stall until commit frees old phys regs)
// - 4-wide rename bundle allocation (unique phys rd)
//
`timescale 1ns / 1ps

module tb_multi_issue_rename_integration;

  parameter int unsigned ARCH_REGS    = 32;
  parameter int unsigned PHYS_REGS    = 64;
  parameter int unsigned ISSUE_WIDTH  = 4;
  parameter int unsigned XLEN         = 32;

  localparam int unsigned PHYS_W = $clog2(PHYS_REGS);

  logic clk, rst_n;

  // Rename interface
  logic [ISSUE_WIDTH-1:0]   rename_valid_i;
  logic [ISSUE_WIDTH*5-1:0] arch_rs1_i;
  logic [ISSUE_WIDTH*5-1:0] arch_rs2_i;
  logic [ISSUE_WIDTH*5-1:0] arch_rd_i;
  logic [ISSUE_WIDTH-1:0]   rename_ready_o;
  logic [ISSUE_WIDTH*PHYS_W-1:0] phys_rs1_o;
  logic [ISSUE_WIDTH*PHYS_W-1:0] phys_rs2_o;
  logic [ISSUE_WIDTH*PHYS_W-1:0] phys_rd_o;
  logic [ISSUE_WIDTH*PHYS_W-1:0] old_phys_rd_o;

  // Commit interface
  logic [ISSUE_WIDTH-1:0]   commit_valid_i;
  logic [ISSUE_WIDTH*PHYS_W-1:0] commit_phys_rd_i;
  logic                     commit_ready_o;

  // Free list status
  logic                     free_list_empty_o;
  logic [$clog2(PHYS_REGS):0] free_count_o;

  // Clock generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Reset generation
  initial begin
    rst_n = 0;
    #50;
    rst_n = 1;
  end

  // DUT
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

  // Test bookkeeping
  int test_count = 0;
  int pass_count = 0;
  int fail_count = 0;

  task automatic check(string name, bit cond);
    test_count++;
    if (cond) begin
      pass_count++;
      $display("[PASS] %s", name);
    end else begin
      fail_count++;
      $display("[FAIL] %s", name);
    end
  endtask

  function automatic int unsigned get_phys(input int unsigned lane, input logic [ISSUE_WIDTH*PHYS_W-1:0] bus);
    get_phys = bus[lane*PHYS_W +: PHYS_W];
  endfunction

  // Store some old phys regs (correct thing to free on commit)
  int unsigned saved_old_phys [0:ISSUE_WIDTH-1];
  int renames;
  int unsigned start_free;
  int unsigned p0, p1, p2, p3;
  logic [4:0] rd_val;

  initial begin
    $display("========================================");
    $display("Multi-Issue + Rename Integration TB");
    $display("Issue width: %0d  Arch regs: %0d  Phys regs: %0d", ISSUE_WIDTH, ARCH_REGS, PHYS_REGS);
    $display("========================================\n");

    rename_valid_i = '0;
    arch_rs1_i = '0;
    arch_rs2_i = '0;
    arch_rd_i  = '0;
    commit_valid_i = '0;
    commit_phys_rd_i = '0;
    for (int k = 0; k < ISSUE_WIDTH; k++) saved_old_phys[k] = 0;

    @(posedge rst_n);
    @(posedge clk);

    check("Initial free_count == 32", free_count_o == (PHYS_REGS - ARCH_REGS));

    // Step 1: Create a few renamed architectural regs and save their old phys mappings.
    // These saved old phys regs are what a real commit would free.
    for (int i = 0; i < ISSUE_WIDTH; i++) begin
      rename_valid_i = '0;
      arch_rs1_i = '0;
      arch_rs2_i = '0;
      arch_rd_i  = '0;

      rename_valid_i[0] = 1'b1;
      arch_rs1_i[0*5 +: 5] = 5'd1;
      arch_rs2_i[0*5 +: 5] = 5'd2;
      rd_val = 5'd5 + i; // x5..x8
      arch_rd_i[0*5 +: 5]  = rd_val;

      @(posedge clk);
      check($sformatf("Rename x%0d ready", 5 + i), rename_ready_o[0] == 1'b1);

      saved_old_phys[i] = get_phys(0, old_phys_rd_o);
      $display("    Saved old phys for x%0d = %0d", 5 + i, saved_old_phys[i]);

      rename_valid_i = '0;
      @(posedge clk);
    end

    // Step 2: Exhaust the free list (single-lane) to force backpressure.
    renames = 0;
    start_free = free_count_o;
    for (int i = 0; i < (start_free + 5); i++) begin
      rename_valid_i = '0;
      arch_rs1_i = '0;
      arch_rs2_i = '0;
      arch_rd_i  = '0;

      rename_valid_i[0] = 1'b1;
      arch_rs1_i[0*5 +: 5] = 5'd1;
      arch_rs2_i[0*5 +: 5] = 5'd2;
      rd_val = 5'd15 + (i % 16); // x15..x30
      arch_rd_i[0*5 +: 5]  = rd_val;

      @(posedge clk);
      if (rename_ready_o[0]) renames++;

      rename_valid_i = '0;
      @(posedge clk);
    end

    check("Renames reached free-list depth", renames == start_free);
    check("Free list empty asserted", free_list_empty_o == 1'b1);

    // Step 3: Demonstrate 'stall until commit' for a 4-wide bundle.
    if (free_count_o < ISSUE_WIDTH) begin
      $display("    Bundle would stall: free_count=%0d, need=%0d", free_count_o, ISSUE_WIDTH);
    end
    check("Backpressure condition present (free_count < ISSUE_WIDTH)", free_count_o < ISSUE_WIDTH);

    // Commit the saved old phys regs (freeing resources for the next bundle).
    commit_valid_i = '0;
    commit_phys_rd_i = '0;
    for (int i = 0; i < ISSUE_WIDTH; i++) begin
      commit_valid_i[i] = 1'b1;
      commit_phys_rd_i[i*PHYS_W +: PHYS_W] = saved_old_phys[i][PHYS_W-1:0];
    end
    @(posedge clk);
    commit_valid_i = '0;
    commit_phys_rd_i = '0;
    @(posedge clk);
    @(posedge clk);

    check("Free list refilled enough for 4-wide", free_count_o >= ISSUE_WIDTH);

    // Step 4: Issue one 4-wide rename bundle and ensure all lanes get unique phys rd.
    rename_valid_i = '0;
    arch_rs1_i = '0;
    arch_rs2_i = '0;
    arch_rd_i  = '0;
    for (int lane = 0; lane < ISSUE_WIDTH; lane++) begin
      rename_valid_i[lane] = 1'b1;
      arch_rs1_i[lane*5 +: 5] = 5'd1;
      arch_rs2_i[lane*5 +: 5] = 5'd2;
      rd_val = 5'd10 + lane; // x10..x13
      arch_rd_i[lane*5 +: 5]  = rd_val;
    end

    @(posedge clk);
    check("All 4 lanes ready", rename_ready_o == {ISSUE_WIDTH{1'b1}});

    p0 = get_phys(0, phys_rd_o);
    p1 = get_phys(1, phys_rd_o);
    p2 = get_phys(2, phys_rd_o);
    p3 = get_phys(3, phys_rd_o);
    $display("    Alloc phys_rd: [%0d %0d %0d %0d]", p0, p1, p2, p3);
    check("phys_rd unique", (p0!=p1) && (p0!=p2) && (p0!=p3) && (p1!=p2) && (p1!=p3) && (p2!=p3));

    rename_valid_i = '0;
    @(posedge clk);

    $display("\n========================================");
    $display("Test Summary");
    $display("Total: %0d  Passed: %0d  Failed: %0d", test_count, pass_count, fail_count);
    if (fail_count == 0) $display("ALL TESTS PASSED!");
    else $display("SOME TESTS FAILED!");
    $display("========================================\n");

    #50;
    $finish;
  end

endmodule

