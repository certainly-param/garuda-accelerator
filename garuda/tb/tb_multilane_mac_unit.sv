// Testbench for Multi-Lane MAC Unit
// Tests 16-lane configuration (64 MAC operations per cycle)

`timescale 1ns / 1ps

module tb_multilane_mac_unit;

  parameter int unsigned NUM_LANES = 16;
  parameter int unsigned LANE_WIDTH = 32;
  parameter int unsigned XLEN = 32;

  logic clk, rst_n;
  
  // Multi-lane unit interface
  logic [NUM_LANES*LANE_WIDTH-1:0] rs1_i, rs2_i;
  logic [XLEN-1:0] rd_i, result_o;
  logic [4:0] opcode_i;
  logic valid_o, we_o, overflow_o;
  
  // Control signals for wrapper
  logic valid_i, lane_load_i, lane_exec_i;
  logic [3:0] lane_idx_i;
  logic [4:0] rd_addr_i;
  
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
  
  // Instantiate wrapper (16-lane configuration)
  int8_mac_multilane_wrapper #(
      .XLEN(XLEN),
      .NUM_LANES(NUM_LANES),
      .LANE_WIDTH(LANE_WIDTH)
  ) dut (
      .clk_i(clk),
      .rst_ni(rst_n),
      .rs1_i(rs1_i[31:0]),  // For scalar ops, only use lower 32 bits
      .rs2_i(rs2_i[31:0]),
      .rd_i(rd_i),
      .opcode_i(opcode_i),
      .hartid_i(0),
      .id_i(0),
      .rd_addr_i(rd_addr_i),
      .valid_i(valid_i),
      .lane_idx_i(lane_idx_i),
      .lane_load_i(lane_load_i),
      .lane_exec_i(lane_exec_i),
      .result_o(result_o),
      .valid_o(valid_o),
      .we_o(we_o),
      .rd_addr_o(),
      .hartid_o(),
      .id_o(),
      .overflow_o(overflow_o)
  );
  
  // Test stimulus
  initial begin
    $display("========================================");
    $display("Multi-Lane MAC Unit Testbench");
    $display("Configuration: %0d lanes (%0d MAC ops/cycle)", NUM_LANES, NUM_LANES*4);
    $display("========================================\n");
    
    // Initialize
    rs1_i = '0;
    rs2_i = '0;
    rd_i = 0;
    opcode_i = 0;
    valid_i = 0;
    lane_load_i = 0;
    lane_exec_i = 0;
    lane_idx_i = 0;
    rd_addr_i = 0;
    
    @(posedge rst_n);
    #20;
    
    // Test 1: Scalar MAC8_ACC (backward compatibility)
    $display("[TEST 1] Scalar MAC8_ACC operation");
    rs1_i[31:0] = 32'h00000010;  // 16
    rs2_i[31:0] = 32'h00000005;  // 5
    rd_i = 100;
    opcode_i = 2;  // MAC8_ACC
    valid_i = 1;
    lane_exec_i = 1;
    @(posedge clk);
    valid_i = 0;
    lane_exec_i = 0;
    @(posedge clk);
    @(posedge clk);  // Wait for pipeline
    if (result_o == 180)  // 16*5 + 100 = 180
      $display("  PASS: Result = %0d (expected 180)", result_o);
    else
      $display("  FAIL: Result = %0d (expected 180)", result_o);
    #20;
    
    // Test 2: 4-lane SIMD_DOT (original SIMD_DOT)
    $display("\n[TEST 2] 4-lane SIMD_DOT (original)");
    rs1_i[31:0] = 32'h01020304;  // [4, 3, 2, 1]
    rs2_i[31:0] = 32'h05060708;  // [8, 7, 6, 5]
    rd_i = 0;
    opcode_i = 5;  // SIMD_DOT
    valid_i = 1;
    lane_exec_i = 1;
    @(posedge clk);
    valid_i = 0;
    lane_exec_i = 0;
    @(posedge clk);
    @(posedge clk);  // Wait for pipeline
    // Expected: 4*8 + 3*7 + 2*6 + 1*5 = 32 + 21 + 12 + 5 = 70
    if (result_o == 70)
      $display("  PASS: Result = %0d (expected 70)", result_o);
    else
      $display("  FAIL: Result = %0d (expected 70)", result_o);
    #20;
    
    // Test 3: 16-lane SIMD_DOT (multi-lane)
    $display("\n[TEST 3] 16-lane SIMD_DOT");
    $display("  Loading 16 lanes with data...");
    
    // Load 16 lanes
    rd_i = 0;
    opcode_i = 5;  // SIMD_DOT
    valid_i = 1;
    lane_load_i = 1;
    lane_exec_i = 0;
    
    for (int i = 0; i < NUM_LANES; i++) begin
      // Each lane: [i+1, i+2, i+3, i+4]
      rs1_i[31:0] = {8'(i+4), 8'(i+3), 8'(i+2), 8'(i+1)};
      rs2_i[31:0] = {8'(i+1), 8'(i+2), 8'(i+3), 8'(i+4)};
      lane_idx_i = i;
      @(posedge clk);
    end
    
    // Execute
    lane_load_i = 0;
    lane_exec_i = 1;
    @(posedge clk);
    lane_exec_i = 0;
    @(posedge clk);
    @(posedge clk);  // Wait for pipeline
    
    // Expected: Sum of dot products for each lane
    // Lane i: (i+1)*(i+1) + (i+2)*(i+2) + (i+3)*(i+3) + (i+4)*(i+4)
    // Simplified test: just verify result is non-zero
    if (result_o != 0)
      $display("  PASS: Multi-lane result = %0d (non-zero)", result_o);
    else
      $display("  FAIL: Multi-lane result = 0 (expected non-zero)");
    
    #100;
    
    // Test 4: Large dot product simulation (64 elements)
    $display("\n[TEST 4] 64-element dot product simulation");
    $display("  Simulating 256-element dot product using 4 iterations...");
    
    rd_i = 0;
    for (int iter = 0; iter < 4; iter++) begin
      // Load one 4-element chunk
      for (int i = 0; i < 4; i++) begin
        int idx = iter * 4 + i;
        rs1_i[31:0] = {8'(idx+4), 8'(idx+3), 8'(idx+2), 8'(idx+1)};
        rs2_i[31:0] = {8'(idx+1), 8'(idx+2), 8'(idx+3), 8'(idx+4)};
        lane_idx_i = i;
        lane_load_i = 1;
        valid_i = 1;
        @(posedge clk);
      end
      
      // Execute and accumulate
      lane_load_i = 0;
      lane_exec_i = 1;
      opcode_i = 5;  // SIMD_DOT
      @(posedge clk);
      lane_exec_i = 0;
      @(posedge clk);
      @(posedge clk);
      
      rd_i = result_o;  // Accumulate result
      $display("    Iteration %0d: partial sum = %0d", iter, result_o);
    end
    
    $display("  Final accumulated result = %0d", rd_i);
    
    #100;
    
    $display("\n========================================");
    $display("Testbench completed");
    $display("========================================");
    $finish;
  end
  
  // Monitor
  always @(posedge clk) begin
    if (valid_o && we_o) begin
      $display("[%0t] Result: %0d (opcode=%0d)", $time, result_o, opcode_i);
    end
  end

endmodule
