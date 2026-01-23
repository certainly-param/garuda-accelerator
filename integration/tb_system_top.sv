// Testbench for CVA6 + Garuda system integration
// Tests the full system with memory connected via NoC interface

`timescale 1ns / 1ps

`include "test_programs.svh"

module tb_system_top;

  // Clock and reset
  logic clk = 0;
  logic rst_n = 0;

  // Clock generation
  always #5 clk = ~clk;  // 100MHz clock (10ns period)

  // Reset generation
  initial begin
    rst_n = 0;
    #100;
    rst_n = 1;
    $display("[%0t] Reset released", $time);
  end

  // Test parameters
  localparam logic [31:0] BOOT_ADDR = 32'h8000_0000;
  localparam logic [31:0] HART_ID = 32'h0;

  // Instantiate system top
  system_top #(
      // Uses default CVA6Cfg (cv32a60x)
  ) dut (
      .clk_i(clk),
      .rst_ni(rst_n),
      .boot_addr_i(BOOT_ADDR),
      .hart_id_i(HART_ID),
      .irq_i(2'b00),
      .ipi_i(1'b0),
      .time_irq_i(1'b0),
      .debug_req_i(1'b0)
  );

  // Memory initialization task
  task init_memory();
    int i;
    int byte_addr;
    int word_idx;
    int byte_offset;
    logic [63:0] mem_data;
    
    $display("[%0t] Initializing memory with test program", $time);
    $display("[%0t] Boot address: 0x%08x", $time, BOOT_ADDR);
    
    // Load test program starting at boot address
    // Memory model: 64-bit words, byte-addressable via AXI
    // Word index = (byte_addr - MEM_BASE) / 8
    // For each 32-bit instruction, pack into appropriate 64-bit word
    
    // Initialize all words to 0 first
    for (i = 0; i < 1024; i++) begin
      dut.i_memory.mem[i] = 64'h0;
    end
    
    // Load instructions
    for (i = 0; i < test_programs_pkg::TEST_PROGRAM_SIZE / 4; i++) begin
      byte_addr = BOOT_ADDR + (i * 4);
      word_idx = (byte_addr - 32'h8000_0000) / 8;  // 64-bit word index
      byte_offset = (byte_addr - 32'h8000_0000) % 8;  // Byte offset within word
      
      // Read current word value (if exists)
      mem_data = dut.i_memory.mem[word_idx];
      
      // Write 32-bit instruction to appropriate byte position
      case (byte_offset)
        0: mem_data[31:0] = test_programs_pkg::TEST_PROGRAM[i];
        4: mem_data[63:32] = test_programs_pkg::TEST_PROGRAM[i];
        default: begin
          $warning("[%0t] Unaligned instruction address: 0x%08x", $time, byte_addr);
          mem_data[31:0] = test_programs_pkg::TEST_PROGRAM[i];  // Default to lower 32 bits
        end
      endcase
      
      dut.i_memory.mem[word_idx] = mem_data;
      $display("[%0t]   [0x%08x] mem[%0d][%0d:%0d] = 0x%08x", 
               $time, byte_addr, word_idx, 
               (byte_offset == 0) ? 31 : 63, 
               (byte_offset == 0) ? 0 : 32,
               test_programs_pkg::TEST_PROGRAM[i]);
    end
    
    $display("[%0t] Memory initialization complete", $time);
  endtask

  // Test monitor - check for completion or timeout
  initial begin
    // Initialize memory before reset release
    init_memory();
    
    // Wait for reset release
    wait(rst_n);
    #10;

    $display("[%0t] ========================================", $time);
    $display("[%0t] Starting CVA6 + Garuda integration test", $time);
    $display("[%0t] ========================================", $time);
    $display("[%0t] System: CVA6 + Garuda + Memory", $time);
    $display("[%0t] Boot address: 0x%08x", $time, BOOT_ADDR);
    $display("[%0t] Test program loaded: %0d instructions", $time, test_programs_pkg::TEST_PROGRAM_SIZE / 4);

    // Monitor execution
    $display("[%0t] CVA6 should now fetch and execute instructions...", $time);
    $display("[%0t] Waiting for test completion...", $time);

    // Run for a fixed duration or until completion
    // Wait longer to allow program execution
    #50000;  // Run for 50us (adjust as needed)

    // Check results if program completed
    // For now, just report timeout
    $display("[%0t] ========================================", $time);
    $display("[%0t] Test completed (timeout)", $time);
    $display("[%0t] ========================================", $time);
    $finish;
  end

  // Waveform dump (optional - for debugging)
  initial begin
    if ($test$plusargs("dump")) begin
      $dumpfile("tb_system_top.vcd");
      $dumpvars(0, tb_system_top);
      $display("[%0t] Waveform dump enabled: tb_system_top.vcd", $time);
    end
  end

endmodule
