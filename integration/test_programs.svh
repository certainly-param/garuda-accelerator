// Test programs for CVA6 + Garuda integration testing
// These are RISC-V 32-bit instruction sequences

package test_programs_pkg;

  // Simple test: Load values, execute MAC8, store result
  // Test sequence:
  //   1. li x1, 0x01020304  (load test data into rs1)
  //   2. li x2, 0x05060708  (load test data into rs2)  
  //   3. li x3, 0           (clear accumulator)
  //   4. mac8 x3, x1, x2    (custom instruction: x3 = x3 + (x1[7:0] * x2[7:0]))
  //   5. sw x3, 0(x0)       (store result to memory)
  //   6. ebreak             (halt)
  
  // RISC-V instruction encodings (32-bit):
  // addi rd, rs1, imm12  = imm12[11:0] rs1[4:0] 000 rd[4:0] 0010011
  // sw rs2, offset(rs1)  = offset[11:5] rs2 rs1 010 offset[4:0] 0100011
  // ebreak               = 000000000001_00000_000_00000_1110011
  
  // li x1, 0x01020304 = lui x1, 0x0102 + addi x1, x1, 0x0304
  // lui x1, 0x0102 = 00000000000100000010 x1 0110111 = 0x01020093
  // Actually, simpler: addi with small values
  // li x1, 0x04 = addi x1, x0, 4 = 0x00408093
  // For larger values, we'll use simpler pattern
  
  // Let's use simple values that fit in 12-bit immediates:
  // li x1, 0x05 (5) = addi x1, x0, 5 = 0x00508093
  // li x2, 0x07 (7) = addi x2, x0, 7 = 0x00710113
  // li x3, 0    = addi x3, x0, 0 = 0x00018193
  
  // MAC8 encoding: 32'b0000000_rs2_rs1_000_rd_1111011
  // MAC8 x3, x1, x2 = 0000000_00010_00001_000_00011_1111011 = 0x002080BB
  
  // sw x3, 0(x0) = 0000000_00011_00000_010_00000_0100011 = 0x00302023
  
  // Program at boot address (0x8000_0000):
  parameter int unsigned TEST_PROGRAM_SIZE = 32;  // 8 instructions * 4 bytes
  parameter logic [31:0] TEST_PROGRAM [0:7] = '{
      32'h00508093,  // addi x1, x0, 5      (x1 = 5)
      32'h00710113,  // addi x2, x0, 7      (x2 = 7)
      32'h00018193,  // addi x3, x0, 0      (x3 = 0, accumulator)
      32'h002080BB,  // custom-3: MAC8 x3, x1, x2  (x3 = x3 + (5 * 7) = 0 + 35 = 35)
      32'h00302023,  // sw x3, 0(x0)        (store result to mem[0])
      32'h00100073,  // ebreak              (halt/trap for debugger)
      32'h00000013,  // nop                 (filler)
      32'h00000013   // nop                 (filler)
  };

endpackage
