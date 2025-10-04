// Simple standalone testbench for Garuda MAC unit
// Tests core functionality without complex package dependencies

`timescale 1ns/1ps

module tb_simple;

  parameter int XLEN = 32;
  parameter int CLK_PERIOD = 10;
  
  typedef enum logic [3:0] {
    ILLEGAL  = 4'b0000,
    MAC8     = 4'b0001,
    MAC8_ACC = 4'b0010,
    MUL8     = 4'b0011,
    CLIP8    = 4'b0100
  } opcode_t;
  
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
  
  int test_num = 0;
  int pass_cnt = 0;
  int fail_cnt = 0;

  // DUT instantiation
  int8_mac_unit #(
      .XLEN(XLEN),
      .opcode_t(opcode_t),
      .hartid_t(logic [1:0]),
      .id_t(logic [2:0])
  ) dut (
      .clk_i(clk),
      .rst_ni(rst_n),
      .rs1_i(rs1),
      .rs2_i(rs2),
      .rd_i(rd_in),
      .opcode_i(opcode),
      .hartid_i(hartid_in),
      .id_i(id_in),
      .rd_addr_i(rd_addr_in),
      .result_o(result),
      .valid_o(valid),
      .we_o(we),
      .rd_addr_o(rd_addr_out),
      .hartid_o(hartid_out),
      .id_o(id_out)
  );

  // Clock
  initial begin
    clk = 0;
    forever #(CLK_PERIOD/2) clk = ~clk;
  end

  // Test
  initial begin
    $display("========================================");
    $display("Garuda MAC Unit - Simple Test");
    $display("========================================\n");
    
    // Reset
    rst_n = 0;
    rs1 = 0; rs2 = 0; rd_in = 0;
    opcode = ILLEGAL;
    hartid_in = 0; id_in = 0; rd_addr_in = 0;
    #(CLK_PERIOD*2);
    rst_n = 1;
    #CLK_PERIOD;
    
    // Test 1: MAC8_ACC - Basic
    test_num = 1;
    $display("Test %0d: MAC8_ACC - Basic (5*3+10)", test_num);
    rs1 = 5; rs2 = 3; rd_in = 10;
    opcode = MAC8_ACC;
    #(CLK_PERIOD*2);
    if ($signed(result) == 25 && valid && we) begin
      $display("  PASS: Result = %0d\n", $signed(result));
      pass_cnt++;
    end else begin
      $display("  FAIL: Expected 25, got %0d\n", $signed(result));
      fail_cnt++;
    end
    
    // Test 2: Negative
    test_num = 2;
    $display("Test %0d: MAC8_ACC - Negative (-5*3+0)", test_num);
    rs1 = -5; rs2 = 3; rd_in = 0;
    opcode = MAC8_ACC;
    #(CLK_PERIOD*2);
    if ($signed(result) == -15 && valid && we) begin
      $display("  PASS: Result = %0d\n", $signed(result));
      pass_cnt++;
    end else begin
      $display("  FAIL: Expected -15, got %0d\n", $signed(result));
      fail_cnt++;
    end
    
    // Test 3: MUL8
    test_num = 3;
    $display("Test %0d: MUL8 (7*8)", test_num);
    rs1 = 7; rs2 = 8; rd_in = 0;
    opcode = MUL8;
    #(CLK_PERIOD*2);
    if ($signed(result) == 56 && valid && we) begin
      $display("  PASS: Result = %0d\n", $signed(result));
      pass_cnt++;
    end else begin
      $display("  FAIL: Expected 56, got %0d\n", $signed(result));
      fail_cnt++;
    end
    
    // Test 4: CLIP8 - Upper saturation
    test_num = 4;
    $display("Test %0d: CLIP8 - Upper (200)", test_num);
    rs1 = 200; rs2 = 0; rd_in = 0;
    opcode = CLIP8;
    #(CLK_PERIOD*2);
    if ($signed(result) == 127 && valid && we) begin
      $display("  PASS: Result = %0d\n", $signed(result));
      pass_cnt++;
    end else begin
      $display("  FAIL: Expected 127, got %0d\n", $signed(result));
      fail_cnt++;
    end
    
    // Test 5: CLIP8 - Lower saturation
    test_num = 5;
    $display("Test %0d: CLIP8 - Lower (-200)", test_num);
    rs1 = -200; rs2 = 0; rd_in = 0;
    opcode = CLIP8;
    #(CLK_PERIOD*2);
    if ($signed(result) == -128 && valid && we) begin
      $display("  PASS: Result = %0d\n", $signed(result));
      pass_cnt++;
    end else begin
      $display("  FAIL: Expected -128, got %0d\n", $signed(result));
      fail_cnt++;
    end
    
    // Test 6: MAC8 - With saturation
    test_num = 6;
    $display("Test %0d: MAC8 - Overflow (100*1+50)", test_num);
    rs1 = 100; rs2 = 1; rd_in = 50;
    opcode = MAC8;
    #(CLK_PERIOD*2);
    if ($signed(result) == 127 && valid && we) begin
      $display("  PASS: Result = %0d (saturated)\n", $signed(result));
      pass_cnt++;
    end else begin
      $display("  FAIL: Expected 127, got %0d\n", $signed(result));
      fail_cnt++;
    end
    
    #(CLK_PERIOD*5);
    
    $display("========================================");
    $display("Test Summary: %0d/%0d passed", pass_cnt, test_num);
    $display("========================================\n");
    
    if (fail_cnt == 0) begin
      $display("ALL TESTS PASSED!\n");
    end else begin
      $display("SOME TESTS FAILED\n");
    end
    
    $finish;
  end

endmodule

