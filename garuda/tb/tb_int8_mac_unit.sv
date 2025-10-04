// Testbench for INT8 MAC execution unit

`timescale 1ns/1ps

module tb_int8_mac_unit;
  import int8_mac_instr_pkg::*;

  parameter int XLEN = 32;
  parameter int CLK_PERIOD = 10;
  
  logic               clk, rst_n;
  logic [XLEN-1:0]    rs1, rs2, rd_in;
  opcode_t            opcode;
  logic [1:0]         hartid_in;
  logic [2:0]         id_in;
  logic [4:0]         rd_addr_in;
  logic [XLEN-1:0]    result;
  logic               valid, we;
  logic [4:0]         rd_addr_out;
  logic [1:0]         hartid_out;
  logic [2:0]         id_out;
  
  int test_count = 0;
  int pass_count = 0;
  int fail_count = 0;

  int8_mac_unit #(
      .XLEN     (XLEN),
      .opcode_t (opcode_t),
      .hartid_t (logic [1:0]),
      .id_t     (logic [2:0])
  ) dut (
      .clk_i      (clk),
      .rst_ni     (rst_n),
      .rs1_i      (rs1),
      .rs2_i      (rs2),
      .rd_i       (rd_in),
      .opcode_i   (opcode),
      .hartid_i   (hartid_in),
      .id_i       (id_in),
      .rd_addr_i  (rd_addr_in),
      .result_o   (result),
      .valid_o    (valid),
      .we_o       (we),
      .rd_addr_o  (rd_addr_out),
      .hartid_o   (hartid_out),
      .id_o       (id_out)
  );

  initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  task automatic reset();
    rst_n = 0;
    rs1 = 0;
    rs2 = 0;
    rd_in = 0;
    opcode = ILLEGAL;
    hartid_in = 0;
    id_in = 0;
    rd_addr_in = 0;
    repeat(2) @(posedge clk);
    rst_n = 1;
    @(posedge clk);
  endtask
  
  task automatic test_mac(
      input string test_name,
      input opcode_t op,
      input logic signed [31:0] a, b, acc,
      input logic signed [31:0] expected
  );
    test_count++;
    $display("[TEST %0d] %s", test_count, test_name);
    $display("  Inputs:  a=%0d, b=%0d, acc=%0d", a, b, acc);
    $display("  Opcode:  %s", opcode_to_string(op));
    
    rs1 = a;
    rs2 = b;
    rd_in = acc;
    opcode = op;
    hartid_in = test_count[1:0];
    id_in = test_count[2:0];
    rd_addr_in = test_count[4:0];
    
    @(posedge clk);
    @(posedge clk);
    
    $display("  Result:  %0d (expected %0d)", $signed(result), expected);
    $display("  Valid:   %b, WE: %b", valid, we);
    
    if ($signed(result) == expected && valid && we) begin
      $display("  ✓ PASS\n");
      pass_count++;
    end else begin
      $display("  ✗ FAIL\n");
      fail_count++;
    end
  endtask

  initial begin
    $display("========================================");
    $display("INT8 MAC Unit Testbench");
    $display("========================================\n");
    
    reset();
    
    $display("\n==== Test Group 1: MAC8.ACC ====\n");
    test_mac("Basic MAC: 5 * 3 + 10", MAC8_ACC, 5, 3, 10, 25);
    test_mac("Zero multiply: 0 * 5 + 10", MAC8_ACC, 0, 5, 10, 10);
    test_mac("Negative: -5 * 3 + 0", MAC8_ACC, -5, 3, 0, -15);
    test_mac("Both negative: -5 * -3 + 0", MAC8_ACC, -5, -3, 0, 15);
    test_mac("Large accumulation: 127 * 127 + 0", MAC8_ACC, 127, 127, 0, 16129);
    test_mac("Multi-accumulate step 1", MAC8_ACC, 10, 10, 0, 100);
    test_mac("Multi-accumulate step 2", MAC8_ACC, 20, 5, 100, 200);
    test_mac("Multi-accumulate step 3", MAC8_ACC, 3, 7, 200, 221);
    
    $display("\n==== Test Group 2: MUL8 ====\n");
    test_mac("Basic mul: 7 * 8", MUL8, 7, 8, 0, 56);
    test_mac("Negative mul: -7 * 8", MUL8, -7, 8, 0, -56);
    test_mac("Max mul: 127 * 1", MUL8, 127, 1, 0, 127);
    test_mac("Max negative mul: -128 * 1", MUL8, -128, 1, 0, -128);
    
    $display("\n==== Test Group 3: CLIP8 ====\n");
    test_mac("In range: clip(50)", CLIP8, 50, 0, 0, 50);
    test_mac("Upper saturate: clip(200)", CLIP8, 200, 0, 0, 127);
    test_mac("Lower saturate: clip(-200)", CLIP8, -200, 0, 0, -128);
    test_mac("At positive boundary: clip(127)", CLIP8, 127, 0, 0, 127);
    test_mac("At negative boundary: clip(-128)", CLIP8, -128, 0, 0, -128);
    test_mac("Just over positive: clip(128)", CLIP8, 128, 0, 0, 127);
    test_mac("Just over negative: clip(-129)", CLIP8, -129, 0, 0, -128);
    
    $display("\n==== Test Group 4: MAC8 ====\n");
    test_mac("Normal MAC8: 5 * 3 + 10", MAC8, 5, 3, 10, 25);
    test_mac("Overflow: 100 * 1 + 50", MAC8, 100, 1, 50, 127);
    test_mac("Underflow: -100 * 1 - 50", MAC8, -100, 1, -50, -128);
    test_mac("At boundary: 64 * 2 - 1", MAC8, 64, 2, -1, 127);
    
    $display("\n==== Test Group 5: Edge Cases ====\n");
    test_mac("All zeros", MAC8_ACC, 0, 0, 0, 0);
    test_mac("Multiply by 1", MAC8_ACC, 42, 1, 0, 42);
    test_mac("Multiply by -1", MAC8_ACC, 42, -1, 0, -42);
    test_mac("Max * Max", MUL8, 127, 127, 0, 16129);
    test_mac("Min * Min", MUL8, -128, -128, 0, 16384);
    
    repeat(5) @(posedge clk);
    
    $display("\n========================================");
    $display("Test Summary");
    $display("========================================");
    $display("Total Tests: %0d", test_count);
    $display("Passed:      %0d", pass_count);
    $display("Failed:      %0d", fail_count);
    
    if (fail_count == 0) begin
      $display("\n🎉 ALL TESTS PASSED! 🎉\n");
    end else begin
      $display("\n❌ SOME TESTS FAILED ❌\n");
    end
    
    $finish;
  end
  
  initial begin
    #(CLK_PERIOD * 10000);
    $display("\n❌ TIMEOUT");
    $finish;
  end

endmodule
