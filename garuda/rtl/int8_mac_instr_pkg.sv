// INT8 MAC Instruction Package
// Defines custom RISC-V instructions for INT8 multiply-accumulate operations

package int8_mac_instr_pkg;

  typedef enum logic [3:0] {
    ILLEGAL           = 4'b0000,
    MAC8              = 4'b0001,  // INT8 MAC with 8-bit accumulator
    MAC8_ACC          = 4'b0010,  // INT8 MAC with 32-bit accumulator
    MUL8              = 4'b0011,  // INT8 multiply
    CLIP8             = 4'b0100,  // Saturate to INT8 range
    SIMD_DOT          = 4'b0101,  // 4-element SIMD Dot Product
    SIMD_DOT_LOAD     = 4'b0110,  // Load lane for multi-lane SIMD_DOT
    SIMD_DOT_EXEC     = 4'b0111,  // Execute multi-lane SIMD_DOT

    // Attention-oriented microkernel ops (latency mode)
    // NOTE: encodings are reserved under custom-3 (0x7B) for future CVXIF integration.
    ATT_DOT_SETUP     = 4'b1000,  // Configure dot microkernel (K, scale/clip params, etc.)
    ATT_DOT_RUN       = 4'b1001,  // Run dot microkernel (baseline acc32)
    ATT_DOT_RUN_SCALE = 4'b1010,  // Run + apply scale/shift
    ATT_DOT_RUN_CLIP  = 4'b1011   // Run + apply clamp
  } opcode_t;

  typedef struct packed {
    logic       accept;
    logic       writeback;
    logic [2:0] register_read;
  } issue_resp_t;

  typedef struct packed {
    logic        accept;
    logic [31:0] instr;
  } compressed_resp_t;

  typedef struct packed {
    logic [31:0] instr;
    logic [31:0] mask;
    issue_resp_t resp;
    opcode_t     opcode;
  } copro_issue_resp_t;

  typedef struct packed {
    logic [15:0]      instr;
    logic [15:0]      mask;
    compressed_resp_t resp;
  } copro_compressed_resp_t;

`ifndef GARUDA_SIMPLE_PKG
  parameter int unsigned NbInstr = 11;  // 7 existing + 4 attention microkernel placeholders
  
  // Instruction encodings using custom-3 opcode (0x7B)
  parameter copro_issue_resp_t CoproInstr[NbInstr] = '{
      // MAC8: rd[7:0] = rs1[7:0] * rs2[7:0] + rd[7:0]
      '{
          instr: 32'b0000000_00000_00000_000_00000_1111011,
          mask:  32'b1111111_00000_00000_111_00000_1111111,
          resp: '{accept: 1'b1, writeback: 1'b1, register_read: 3'b011},
          opcode: MAC8
      },
      
      // MAC8.ACC: rd[31:0] = rs1[7:0] * rs2[7:0] + rd[31:0]
      '{
          instr: 32'b0000001_00000_00000_000_00000_1111011,
          mask:  32'b1111111_00000_00000_111_00000_1111111,
          resp: '{accept: 1'b1, writeback: 1'b1, register_read: 3'b011},
          opcode: MAC8_ACC
      },
      
      // MUL8: rd = sign_extend(rs1[7:0] * rs2[7:0])
      '{
          instr: 32'b0000010_00000_00000_000_00000_1111011,
          mask:  32'b1111111_00000_00000_111_00000_1111111,
          resp: '{accept: 1'b1, writeback: 1'b1, register_read: 3'b011},
          opcode: MUL8
      },
      
      // CLIP8: rd = saturate(rs1, -128, 127)
      '{
          instr: 32'b0000011_00000_00000_000_00000_1111011,
          mask:  32'b1111111_11111_00000_111_00000_1111111,
          resp: '{accept: 1'b1, writeback: 1'b1, register_read: 3'b001},
          opcode: CLIP8
      },

      // SIMD_DOT: rd = dot_product(rs1[31:0], rs2[31:0]) + rd
      // Performs 4x INT8 multiplies and adds to 32-bit accumulator
      '{
          instr: 32'b0000100_00000_00000_000_00000_1111011,
          mask:  32'b1111111_00000_00000_111_00000_1111111,
          resp: '{accept: 1'b1, writeback: 1'b1, register_read: 3'b011},
          opcode: SIMD_DOT
      },

      // SIMD_DOT_LOAD: Load one lane (32 bits) for multi-lane operation
      // Lane index encoded in imm[3:0] = instr[11:8]
      // Format: simd_dot_load rd, rs1, rs2, imm[3:0] where imm = lane index
      '{
          instr: 32'b0000101_00000_00000_000_00000_1111011,
          mask:  32'b1111111_00000_00000_111_00000_1111111,
          resp: '{accept: 1'b1, writeback: 1'b0, register_read: 3'b011},  // No writeback during load
          opcode: SIMD_DOT_LOAD
      },

      // SIMD_DOT_EXEC: Execute multi-lane SIMD_DOT after all lanes loaded
      // rd = sum(all lanes) + rd
      '{
          instr: 32'b0000110_00000_00000_000_00000_1111011,
          mask:  32'b1111111_00000_00000_111_00000_1111111,
          resp: '{accept: 1'b1, writeback: 1'b1, register_read: 3'b001},  // Only read rd
          opcode: SIMD_DOT_EXEC
      },

      // ---------------------------------------------------------------------
      // Attention microkernel placeholders (reserved encodings)
      // ---------------------------------------------------------------------

      // ATT_DOT_SETUP: configure parameters (no writeback)
      '{
          instr: 32'b0000111_00000_00000_000_00000_1111011,
          mask:  32'b1111111_00000_00000_111_00000_1111111,
          resp: '{accept: 1'b1, writeback: 1'b0, register_read: 3'b011},
          opcode: ATT_DOT_SETUP
      },

      // ATT_DOT_RUN: run baseline dot (writeback)
      '{
          instr: 32'b0001000_00000_00000_000_00000_1111011,
          mask:  32'b1111111_00000_00000_111_00000_1111111,
          resp: '{accept: 1'b1, writeback: 1'b1, register_read: 3'b011},
          opcode: ATT_DOT_RUN
      },

      // ATT_DOT_RUN_SCALE: run dot + scale/shift (writeback)
      '{
          instr: 32'b0001001_00000_00000_000_00000_1111011,
          mask:  32'b1111111_00000_00000_111_00000_1111111,
          resp: '{accept: 1'b1, writeback: 1'b1, register_read: 3'b011},
          opcode: ATT_DOT_RUN_SCALE
      },

      // ATT_DOT_RUN_CLIP: run dot + clamp (writeback)
      '{
          instr: 32'b0001010_00000_00000_000_00000_1111011,
          mask:  32'b1111111_00000_00000_111_00000_1111111,
          resp: '{accept: 1'b1, writeback: 1'b1, register_read: 3'b011},
          opcode: ATT_DOT_RUN_CLIP
      }
  };

  // Stub for compressed interface (not implemented)
  parameter int unsigned NbCompInstr = 0;
  parameter copro_compressed_resp_t CoproCompInstr[1] = '{
      '{instr: 16'h0000, mask: 16'hFFFF, resp: '{accept: 1'b0, instr: 32'h00000000}}
  };
`else
  // Icarus-friendly mode: omit complex parameter arrays (CoproInstr) to avoid tool limitations.
  parameter int unsigned NbInstr = 0;
  parameter int unsigned NbCompInstr = 0;
`endif

  function automatic string opcode_to_string(opcode_t op);
    case (op)
      MAC8:          return "MAC8";
      MAC8_ACC:      return "MAC8.ACC";
      MUL8:          return "MUL8";
      CLIP8:         return "CLIP8";
      SIMD_DOT:      return "SIMD_DOT";
      SIMD_DOT_LOAD: return "SIMD_DOT_LOAD";
      SIMD_DOT_EXEC: return "SIMD_DOT_EXEC";
      ATT_DOT_SETUP:     return "ATT_DOT_SETUP";
      ATT_DOT_RUN:       return "ATT_DOT_RUN";
      ATT_DOT_RUN_SCALE: return "ATT_DOT_RUN_SCALE";
      ATT_DOT_RUN_CLIP:  return "ATT_DOT_RUN_CLIP";
      ILLEGAL:       return "ILLEGAL";
      default:       return "UNKNOWN";
    endcase
  endfunction

  function automatic opcode_t decode_instr(logic [31:0] instr);
`ifndef GARUDA_SIMPLE_PKG
    for (int i = 0; i < NbInstr; i++) begin
      if ((CoproInstr[i].mask & instr) == CoproInstr[i].instr) begin
        return CoproInstr[i].opcode;
      end
    end
    return ILLEGAL;
`else
    return ILLEGAL;
`endif
  endfunction

endpackage
