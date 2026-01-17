// INT8 MAC Instruction Package
// Defines custom RISC-V instructions for INT8 multiply-accumulate operations

package int8_mac_instr_pkg;

  typedef enum logic [3:0] {
    ILLEGAL  = 4'b0000,
    MAC8     = 4'b0001,  // INT8 MAC with 8-bit accumulator
    MAC8_ACC = 4'b0010,  // INT8 MAC with 32-bit accumulator
    MUL8     = 4'b0011,  // INT8 multiply
    CLIP8    = 4'b0100,  // Saturate to INT8 range
    SIMD_DOT = 4'b0101   // 4-element SIMD Dot Product
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

  parameter int unsigned NbInstr = 5;
  
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
      }
  };

  // Stub for compressed interface (not implemented)
  parameter int unsigned NbCompInstr = 0;
  parameter copro_compressed_resp_t CoproCompInstr[1] = '{
      '{instr: 16'h0000, mask: 16'hFFFF, resp: '{accept: 1'b0, instr: 32'h00000000}}
  };

  function automatic string opcode_to_string(opcode_t op);
    case (op)
      MAC8:     return "MAC8";
      MAC8_ACC: return "MAC8.ACC";
      MUL8:     return "MUL8";
      CLIP8:    return "CLIP8";
      SIMD_DOT: return "SIMD_DOT";
      ILLEGAL:  return "ILLEGAL";
      default:  return "UNKNOWN";
    endcase
  endfunction

  function automatic opcode_t decode_instr(logic [31:0] instr);
    for (int i = 0; i < NbInstr; i++) begin
      if ((CoproInstr[i].mask & instr) == CoproInstr[i].instr) begin
        return CoproInstr[i].opcode;
      end
    end
    return ILLEGAL;
  endfunction

endpackage
