// CVXIF Integration Testbench for Attention Microkernel Engine
// Tests end-to-end flow through CVXIF interface:
// 1. ATT_DOT_SETUP: Configure engine
// 2. Multiple ATT_DOT_RUN: Stage operands
// 3. Verify result writeback
//
// NOTE: This testbench may not compile with Icarus Verilog due to limitations
// with parameter array initialization in packages. It is recommended to use
// Verilator or another SystemVerilog-compliant simulator for this testbench.
// The standalone microkernel engine can be tested with tb_attention_microkernel_latency.sv
// which works with Icarus.
//
`timescale 1ns / 1ps

module tb_attention_microkernel_cvxif;
  
  // Import package (includes full CoproInstr array)
  import int8_mac_instr_pkg::*;

  parameter int unsigned XLEN = 32;
  parameter int unsigned K_ELEMS = 128;  // 128 int8 elements = 32 words
  parameter int unsigned WORD_ELEMS = 4;
  localparam int unsigned K_WORDS = K_ELEMS / WORD_ELEMS;
  
  // Simplified CVXIF types for testbench
  typedef logic [XLEN-1:0] cvxif_reg_t;
  typedef logic [4:0] cvxif_rd_t;
  typedef logic [1:0] cvxif_hartid_t;
  typedef logic [4:0] cvxif_id_t;
  
  typedef struct packed {
    logic valid;
    logic [XLEN-1:0] instr;
    cvxif_hartid_t hartid;
    cvxif_id_t id;
  } cvxif_issue_req_t;
  
  typedef struct packed {
    logic accept;
    logic writeback;
    logic [2:0] register_read;
  } cvxif_issue_resp_t;
  
  typedef struct packed {
    logic [1:0] rs_valid;
    cvxif_reg_t rs [1:0];
  } cvxif_register_t;
  
  typedef struct packed {
    logic valid;
    cvxif_reg_t data;
    cvxif_rd_t rd;
    logic we;
    cvxif_hartid_t hartid;
    cvxif_id_t id;
  } cvxif_result_t;
  
  typedef struct packed {
    cvxif_issue_resp_t issue_resp;
    logic issue_ready;
    logic compressed_ready;
    logic [XLEN-1:0] compressed_resp;
    cvxif_result_t result;
    logic result_valid;
    logic register_ready;
  } cvxif_resp_t;
  
  typedef struct packed {
    cvxif_issue_req_t issue_req;
    logic issue_valid;
    cvxif_register_t register;
    logic register_valid;
    logic compressed_valid;
    logic [15:0] compressed_req;
  } cvxif_req_t;
  
  logic clk, rst_n;
  
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
  
  // CVXIF interface
  cvxif_req_t  cvxif_req;
  cvxif_resp_t cvxif_resp;
  
  // Test data
  logic [31:0] q_words [0:K_WORDS-1];
  logic [31:0] k_words [0:K_WORDS-1];
  integer expected_result;
  
  // Golden reference: compute dot product
  function automatic integer compute_dot_product();
    integer acc;
    integer i, j;
    acc = 0;
    for (i = 0; i < K_WORDS; i++) begin
      for (j = 0; j < WORD_ELEMS; j++) begin
        acc = acc + ($signed(q_words[i][8*j+7:8*j]) * $signed(k_words[i][8*j+7:8*j]));
      end
    end
    return acc;
  endfunction
  
  // Instantiate DUT
  int8_mac_coprocessor #(
      .NrRgprPorts(2),
      .XLEN(XLEN),
      .readregflags_t(logic),
      .writeregflags_t(logic),
      .id_t(cvxif_id_t),
      .hartid_t(cvxif_hartid_t),
      .x_compressed_req_t(logic [15:0]),
      .x_compressed_resp_t(logic [XLEN-1:0]),
      .x_issue_req_t(cvxif_issue_req_t),
      .x_issue_resp_t(cvxif_issue_resp_t),
      .x_register_t(cvxif_register_t),
      .x_commit_t(logic),
      .x_result_t(cvxif_result_t),
      .cvxif_req_t(cvxif_req_t),
      .cvxif_resp_t(cvxif_resp_t)
  ) dut (
      .clk_i(clk),
      .rst_ni(rst_n),
      .cvxif_req_i(cvxif_req),
      .cvxif_resp_o(cvxif_resp)
  );
  
  // Task: Issue instruction through CVXIF
  task issue_instr(
      input logic [31:0] instr,
      input cvxif_reg_t rs1_val,
      input cvxif_reg_t rs2_val,
      input cvxif_hartid_t hartid,
      input cvxif_id_t id
  );
    cvxif_req.issue_req.instr = instr;
    cvxif_req.issue_req.hartid = hartid;
    cvxif_req.issue_req.id = id;
    cvxif_req.issue_valid = 1'b1;
    
    // Wait for ready
    @(posedge clk);
    while (!cvxif_resp.issue_ready) @(posedge clk);
    
    // Provide register values if needed
    if (cvxif_resp.issue_resp.register_read[0] || cvxif_resp.issue_resp.register_read[1]) begin
      cvxif_req.register_valid = 1'b1;
      cvxif_req.register.rs_valid[0] = 1'b1;
      cvxif_req.register.rs_valid[1] = 1'b1;
      cvxif_req.register.rs[0] = rs1_val;
      cvxif_req.register.rs[1] = rs2_val;
    end else begin
      cvxif_req.register_valid = 1'b0;
    end
    
    @(posedge clk);
    cvxif_req.issue_valid = 1'b0;
    cvxif_req.register_valid = 1'b0;
  endtask
  
  // Task: Wait for result
  task wait_for_result(output cvxif_result_t result);
    while (!cvxif_resp.result_valid) @(posedge clk);
    result = cvxif_resp.result;
    @(posedge clk);
  endtask
  
  initial begin
    integer i;
    integer test_num;
    cvxif_result_t result;
    integer cycles_start, cycles_end;
    integer latency;
    integer pass_cnt, fail_cnt;
    
    pass_cnt = 0;
    fail_cnt = 0;
    
    // Initialize CVXIF interface
    cvxif_req = '0;
    cvxif_req.compressed_valid = 1'b0;
    
    // Initialize test data
    for (i = 0; i < K_WORDS; i++) begin
      q_words[i] = $urandom();
      k_words[i] = $urandom();
    end
    
    // Compute expected result
    expected_result = compute_dot_product();
    
    @(posedge rst_n);
    @(posedge clk);
    
    $display("========================================");
    $display("CVXIF Attention Microkernel Integration Test");
    $display("K=%0d int8 elements (%0d words)", K_ELEMS, K_WORDS);
    $display("Expected result: %0d", expected_result);
    $display("========================================\n");
    
    // Test 1: ATT_DOT_SETUP
    test_num = 1;
    $display("Test %0d: ATT_DOT_SETUP", test_num);
    // rs1[7:0] = K, rs1[11:8] = shift, rs2[15:0] = scale
    issue_instr(
        .instr(32'b0000111_00000_00000_000_00000_1111011 | (K_ELEMS << 7) | (4'd1 << 15)),  // K=128, shift=1
        .rs1_val({20'h0, 4'd1, K_ELEMS[7:0]}),  // shift=1, K=128
        .rs2_val(16'h0100),  // scale=1.0 in Q8.8
        .hartid(0),
        .id(1)
    );
    @(posedge clk);
    $display("  SETUP complete\n");
    pass_cnt++;
    
    // Test 2: Stage operands and execute with ATT_DOT_RUN
    test_num = 2;
    $display("Test %0d: ATT_DOT_RUN (stage and execute)", test_num);
    cycles_start = $time / 10;
    
    // Stage all operands (one word pair per instruction)
    for (i = 0; i < K_WORDS; i++) begin
      issue_instr(
          .instr(32'b0001000_00000_00000_000_00010_1111011),  // ATT_DOT_RUN, rd=x2
          .rs1_val(q_words[i]),
          .rs2_val(k_words[i]),
          .hartid(0),
          .id(2 + i)
      );
      @(posedge clk);
    end
    
    // Wait for result
    wait_for_result(result);
    cycles_end = $time / 10;
    latency = cycles_end - cycles_start;
    
    $display("  Result: %0d (expected: %0d)", $signed(result.data), expected_result);
    $display("  Latency: %0d cycles", latency);
    
    if ($signed(result.data) == expected_result && result.valid && result.we) begin
      $display("  PASS\n");
      pass_cnt++;
    end else begin
      $display("  FAIL: Expected %0d, got %0d\n", expected_result, $signed(result.data));
      fail_cnt++;
    end
    
    // Test 3: ATT_DOT_RUN_SCALE (with scaling)
    test_num = 3;
    $display("Test %0d: ATT_DOT_RUN_SCALE (with scaling)", test_num);
    
    // Reconfigure with scale
    issue_instr(
        .instr(32'b0000111_00000_00000_000_00000_1111011 | (K_ELEMS << 7) | (4'd2 << 15)),  // shift=2
        .rs1_val({20'h0, 4'd2, K_ELEMS[7:0]}),
        .rs2_val(16'h0200),  // scale=2.0 in Q8.8
        .hartid(0),
        .id(100)
    );
    @(posedge clk);
    
    cycles_start = $time / 10;
    
    // Stage and execute with scaling
    for (i = 0; i < K_WORDS; i++) begin
      issue_instr(
          .instr(32'b0001001_00000_00000_000_00011_1111011),  // ATT_DOT_RUN_SCALE, rd=x3
          .rs1_val(q_words[i]),
          .rs2_val(k_words[i]),
          .hartid(0),
          .id(101 + i)
      );
      @(posedge clk);
    end
    
    wait_for_result(result);
    cycles_end = $time / 10;
    latency = cycles_end - cycles_start;
    
    // Expected: (dot * 2.0) >> (8 + 2) = (dot * 512) >> 10 = dot >> 1
    integer expected_scaled;
    expected_scaled = expected_result >> 1;
    
    $display("  Result: %0d (expected scaled: %0d)", $signed(result.data), expected_scaled);
    $display("  Latency: %0d cycles", latency);
    
    // Allow some tolerance for fixed-point rounding
    if (($signed(result.data) >= expected_scaled - 1) && 
        ($signed(result.data) <= expected_scaled + 1) &&
        result.valid && result.we) begin
      $display("  PASS (within tolerance)\n");
      pass_cnt++;
    end else begin
      $display("  FAIL: Expected ~%0d, got %0d\n", expected_scaled, $signed(result.data));
      fail_cnt++;
    end
    
    // Summary
    $display("========================================");
    $display("Test Summary: %0d passed, %0d failed", pass_cnt, fail_cnt);
    $display("========================================");
    
    #100;
    $finish;
  end

endmodule
