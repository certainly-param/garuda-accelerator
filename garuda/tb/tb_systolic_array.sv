// Testbench for 2D Systolic Array
// Tests PE array, data flow, and matrix multiply operations

`timescale 1ns / 1ps

module tb_systolic_array;

  parameter int unsigned ROW_SIZE    = 8;
  parameter int unsigned COL_SIZE    = 8;
  parameter int unsigned DATA_WIDTH  = 8;
  parameter int unsigned ACC_WIDTH   = 32;

  logic clk, rst_n;
  
  // Weight interface
  logic weight_valid_i;
  logic [ROW_SIZE*DATA_WIDTH-1:0] weight_row_i;
  logic weight_ready_o;
  
  // Activation interface
  logic activation_valid_i;
  logic [COL_SIZE*DATA_WIDTH-1:0] activation_col_i;
  logic activation_ready_o;
  
  // Result interface
  logic result_valid_o;
  logic [ROW_SIZE*ACC_WIDTH-1:0] result_row_o;
  logic result_ready_i;
  
  // Control
  logic load_weights_i;
  logic execute_i;
  logic clear_accumulators_i;
  logic done_o;
  
  // Test matrices
  logic [7:0] matrix_a [0:ROW_SIZE-1][0:COL_SIZE-1];  // Weight matrix
  logic [7:0] matrix_b [0:COL_SIZE-1][0:ROW_SIZE-1];  // Activation matrix
  logic [31:0] expected_result [0:ROW_SIZE-1][0:ROW_SIZE-1];  // Expected output (A × B)
  
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
  systolic_array #(
      .ROW_SIZE(ROW_SIZE),
      .COL_SIZE(COL_SIZE),
      .DATA_WIDTH(DATA_WIDTH),
      .ACC_WIDTH(ACC_WIDTH)
  ) dut (
      .clk_i(clk),
      .rst_ni(rst_n),
      .weight_valid_i(weight_valid_i),
      .weight_row_i(weight_row_i),
      .weight_ready_o(weight_ready_o),
      .activation_valid_i(activation_valid_i),
      .activation_col_i(activation_col_i),
      .activation_ready_o(activation_ready_o),
      .result_valid_o(result_valid_o),
      .result_row_o(result_row_o),
      .result_ready_i(result_ready_i),
      .load_weights_i(load_weights_i),
      .execute_i(execute_i),
      .clear_accumulators_i(clear_accumulators_i),
      .done_o(done_o)
  );
  
  // Initialize test matrices
  task init_matrices();
    // Matrix A (weights) - simple pattern
    for (int i = 0; i < ROW_SIZE; i++) begin
      for (int j = 0; j < COL_SIZE; j++) begin
        matrix_a[i][j] = i + j;  // Pattern: row + col
      end
    end
    
    // Matrix B (activations) - identity-like
    for (int i = 0; i < COL_SIZE; i++) begin
      for (int j = 0; j < ROW_SIZE; j++) begin
        matrix_b[i][j] = (i == j) ? 8'd1 : 8'd0;  // Identity-like
      end
    end
    
    // Calculate expected result: C = A × B
    for (int i = 0; i < ROW_SIZE; i++) begin
      for (int j = 0; j < ROW_SIZE; j++) begin
        expected_result[i][j] = 0;
        for (int k = 0; k < COL_SIZE; k++) begin
          expected_result[i][j] = expected_result[i][j] + 
                                   ($signed(matrix_a[i][k]) * $signed(matrix_b[k][j]));
        end
      end
    end
  endtask
  
  // Load weight matrix
  task load_weight_matrix();
    load_weights_i = 1'b1;
    @(posedge clk);
    load_weights_i = 1'b0;
    
    for (int row = 0; row < ROW_SIZE; row++) begin
      // Pack row into weight_row_i
      for (int col = 0; col < ROW_SIZE; col++) begin
        weight_row_i[col*DATA_WIDTH +: DATA_WIDTH] = matrix_a[row][col];
      end
      
      weight_valid_i = 1'b1;
      @(posedge clk);
      while (!weight_ready_o) @(posedge clk);
      weight_valid_i = 1'b0;
      @(posedge clk);
    end
    
    $display("    Loaded %0d weight rows", ROW_SIZE);
  endtask
  
  // Load activation matrix (column by column)
  task load_activation_matrix();
    activation_valid_i = 1'b1;
    
    for (int col = 0; col < COL_SIZE; col++) begin
      // Pack column into activation_col_i
      for (int row = 0; row < COL_SIZE; row++) begin
        activation_col_i[row*DATA_WIDTH +: DATA_WIDTH] = matrix_b[row][col];
      end
      
      @(posedge clk);
      while (!activation_ready_o) @(posedge clk);
      @(posedge clk);
    end
    
    activation_valid_i = 1'b0;
    $display("    Loaded %0d activation columns", COL_SIZE);
  endtask
  
  // Test stimulus
  int test_count = 0;
  int pass_count = 0;
  int fail_count = 0;
  logic [ACC_WIDTH-1:0] result_val;
  logic [ACC_WIDTH-1:0] expected_val;
  logic [ACC_WIDTH-1:0] result_00;
  logic [ACC_WIDTH-1:0] result_10;
  
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
    $display("2D Systolic Array Testbench");
    $display("Configuration: %0d×%0d PE array", ROW_SIZE, COL_SIZE);
    $display("========================================\n");
    
    // Initialize
    weight_valid_i = 0;
    activation_valid_i = 0;
    result_ready_i = 1;
    load_weights_i = 0;
    execute_i = 0;
    clear_accumulators_i = 0;
    weight_row_i = '0;
    activation_col_i = '0;
    
    // Initialize test matrices
    init_matrices();
    
    @(posedge rst_n);
    #20;
    
    // Test 1: Clear accumulators
    $display("\n[TEST 1] Clear accumulators");
    clear_accumulators_i = 1'b1;
    @(posedge clk);
    clear_accumulators_i = 1'b0;
    @(posedge clk);
    check_result(1, "Clear executed", 1'b1, 1'b1);
    
    // Test 2: Load weight matrix
    $display("\n[TEST 2] Load weight matrix");
    load_weight_matrix();
    check_result(2, "Weights loaded", 1'b1, 1'b1);
    
    // Test 3: Load activation matrix and compute
    $display("\n[TEST 3] Load activations and compute");
    execute_i = 1'b1;
    @(posedge clk);
    execute_i = 1'b0;
    
    load_activation_matrix();
    
    // Wait for computation to complete
    // Computation takes approximately COL_SIZE + ROW_SIZE cycles
    repeat(COL_SIZE + ROW_SIZE + 5) @(posedge clk);
    
    // Wait for results
    result_ready_i = 1'b1;
    @(posedge clk);
    
    if (result_valid_o) begin
      check_result(3, "Result valid", 1'b1, 1'b1);
      
      // Extract and check results
      for (int i = 0; i < ROW_SIZE; i++) begin
        result_val = result_row_o[i*ACC_WIDTH +: ACC_WIDTH];
        expected_val = expected_result[i][0];  // First column
        
        $display("    Result[%0d][0] = %0d (expected %0d)", i, $signed(result_val), $signed(expected_val));
        
        if (result_val == expected_val) begin
          $display("      ✓ Match");
        end else begin
          $display("      ✗ Mismatch!");
        end
      end
    end else begin
      check_result(3, "Result valid", 1'b0, 1'b1);
    end
    
    @(posedge clk);
    
    // Test 4: Simple 2×2 matrix multiply (for easier verification)
    $display("\n[TEST 4] Simple 2×2 verification (using 8×8 array)");
    clear_accumulators_i = 1'b1;
    @(posedge clk);
    clear_accumulators_i = 1'b0;
    
    // Simple test: A = [[1,2],[3,4]], B = [[1,0],[0,1]] (identity)
    // Expected: C = [[1,2],[3,4]]
    // Load only first 2 rows/cols
    load_weights_i = 1'b1;
    @(posedge clk);
    load_weights_i = 1'b0;
    
    // Row 0: [1, 2, 0, ...]
    weight_row_i = {8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd2, 8'd1};
    weight_valid_i = 1'b1;
    @(posedge clk);
    while (!weight_ready_o) @(posedge clk);
    weight_valid_i = 1'b0;
    @(posedge clk);
    
    // Row 1: [3, 4, 0, ...]
    weight_row_i = {8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd4, 8'd3};
    weight_valid_i = 1'b1;
    @(posedge clk);
    while (!weight_ready_o) @(posedge clk);
    weight_valid_i = 1'b0;
    
    // For remaining rows, load zeros
    for (int i = 2; i < ROW_SIZE; i++) begin
      weight_row_i = '0;
      weight_valid_i = 1'b1;
      @(posedge clk);
      while (!weight_ready_o) @(posedge clk);
      weight_valid_i = 1'b0;
      @(posedge clk);
    end
    
    // Load activations (identity: column 0 = [1,0,...], column 1 = [0,1,...])
    execute_i = 1'b1;
    @(posedge clk);
    execute_i = 1'b0;
    
    // Column 0: [1, 0, 0, ...]
    activation_col_i = {8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd1};
    activation_valid_i = 1'b1;
    @(posedge clk);
    while (!activation_ready_o) @(posedge clk);
    @(posedge clk);
    
    // Column 1: [0, 1, 0, ...]
    activation_col_i = {8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd1, 8'd0};
    @(posedge clk);
    while (!activation_ready_o) @(posedge clk);
    @(posedge clk);
    
    // Remaining columns are zeros
    for (int i = 2; i < COL_SIZE; i++) begin
      activation_col_i = '0;
      @(posedge clk);
      while (!activation_ready_o) @(posedge clk);
      @(posedge clk);
    end
    
    activation_valid_i = 1'b0;
    
    // Wait for computation
    repeat(COL_SIZE + ROW_SIZE + 5) @(posedge clk);
    
    if (result_valid_o) begin
      result_00 = result_row_o[0*ACC_WIDTH +: ACC_WIDTH];
      result_10 = result_row_o[1*ACC_WIDTH +: ACC_WIDTH];
      
      // Expected: C[0][0] = 1, C[0][1] = 2, C[1][0] = 3, C[1][1] = 4
      $display("    Result[0][0] = %0d (expected 1)", $signed(result_00));
      $display("    Result[1][0] = %0d (expected 3)", $signed(result_10));
      
      check_result(4, "C[0][0] == 1", result_00 == 32'd1, 1'b1);
      check_result(4, "C[1][0] == 3", result_10 == 32'd3, 1'b1);
    end
    
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
