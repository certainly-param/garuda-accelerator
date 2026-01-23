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
    ATT_DOT_SETUP     = 4'b1000,  // Configure dot microkernel (K from rs1[7:0], scale from rs2[15:0], shift from rs1[11:8], clip from rd/rs2)
    ATT_DOT_RUN       = 4'b1001,  // Stage operands and run baseline dot: rs1=Q_word, rs2=K_word (stages if not full), then executes if all staged
    ATT_DOT_RUN_SCALE = 4'b1010,  // Run + apply scale/shift (same as RUN but with scale enabled)
    ATT_DOT_RUN_CLIP  = 4'b1011   // Run + apply clamp (same as RUN but with clip enabled)
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
      // Attention microkernel instructions (low-latency dot product)
      // ---------------------------------------------------------------------
      
      // Instruction encoding format:
      // All ATT_DOT_* instructions use custom-3 opcode (0x7B)
      // Bits [31:25] = funct7 (distinguishes instruction type)
      // Bits [24:20] = rs2
      // Bits [19:15] = rs1
      // Bits [14:12] = funct3 (unused/reserved)
      // Bits [11:7]  = rd
      // Bits [6:0]   = opcode (0x7B = custom-3)
      
      // ATT_DOT_SETUP: configure microkernel engine parameters
      // Encoding: 32'b0000111_rs2_rs1_000_rd_1111011
      // rs1[7:0]    = K (number of int8 elements, must be multiple of 4, max 256)
      // rs1[11:8]   = shift (right shift amount, 0-15, applied after scaling)
      // rs2[15:0]   = scale (Q8.8 fixed-point multiplier, signed 16-bit)
      // rs2[31:16]  = unused (reserved)
      // rd          = unused (no writeback)
      // Note: clip_min/clip_max currently default to -32768/32767 (can be extended to use rd/rs2)
      //       Configuration persists until next ATT_DOT_SETUP
      //       Must be called before ATT_DOT_RUN* instructions
      '{
          instr: 32'b0000111_00000_00000_000_00000_1111011,
          mask:  32'b1111111_00000_00000_111_00000_1111111,
          resp: '{accept: 1'b1, writeback: 1'b0, register_read: 3'b011},
          opcode: ATT_DOT_SETUP
      },

      // ATT_DOT_RUN: stage operands and execute (baseline dot product, no post-ops)
      // Encoding: 32'b0001000_rs2_rs1_000_rd_1111011
      // rs1[31:0] = Q_word (packed 4× int8, Q vector word)
      // rs2[31:0] = K_word (packed 4× int8, K vector word)
      // rd        = destination register for result
      // Operation:
      //   1. Stages Q_word and K_word into internal buffers at current word index
      //   2. If all words staged (K/4 words), triggers execution
      //   3. Computes dot product: sum(Q[i] * K[i] for i in 0..K-1)
      //   4. Result: 32-bit signed accumulator (no scaling/clipping)
      // Note: Multiple ATT_DOT_RUN instructions may be needed to stage all operands
      //       (one instruction per 4-element word pair)
      //       Execution occurs automatically when all operands are staged
      '{
          instr: 32'b0001000_00000_00000_000_00000_1111011,
          mask:  32'b1111111_00000_00000_111_00000_1111111,
          resp: '{accept: 1'b1, writeback: 1'b1, register_read: 3'b011},
          opcode: ATT_DOT_RUN
      },

      // ATT_DOT_RUN_SCALE: stage operands and execute with scaling
      // Encoding: 32'b0001001_rs2_rs1_000_rd_1111011
      // rs1[31:0] = Q_word (packed 4× int8, Q vector word)
      // rs2[31:0] = K_word (packed 4× int8, K vector word)
      // rd        = destination register for result
      // Operation: Same as ATT_DOT_RUN, but applies post-op scaling:
      //   result = (dot_product * scale) >> (8 + shift)
      //   where scale and shift come from previous ATT_DOT_SETUP
      //   This enables attention score normalization (e.g., 1/sqrt(d_k))
      '{
          instr: 32'b0001001_00000_00000_000_00000_1111011,
          mask:  32'b1111111_00000_00000_111_00000_1111111,
          resp: '{accept: 1'b1, writeback: 1'b1, register_read: 3'b011},
          opcode: ATT_DOT_RUN_SCALE
      },

      // ATT_DOT_RUN_CLIP: stage operands and execute with scaling and clipping
      // Encoding: 32'b0001010_rs2_rs1_000_rd_1111011
      // rs1[31:0] = Q_word (packed 4× int8, Q vector word)
      // rs2[31:0] = K_word (packed 4× int8, K vector word)
      // rd        = destination register for result
      // Operation: Same as ATT_DOT_RUN_SCALE, but also applies clipping:
      //   scaled = (dot_product * scale) >> (8 + shift)
      //   result = clamp(scaled, clip_min, clip_max)
      //   where clip_min/clip_max come from previous ATT_DOT_SETUP (or defaults)
      //   This enables softmax input clamping for numerical stability
      '{
          instr: 32'b0001010_00000_00000_000_00000_1111011,
          mask:  32'b1111111_00000_00000_111_00000_1111011,
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
