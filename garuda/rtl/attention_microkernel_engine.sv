// Attention Microkernel Engine (latency mode)
// Goal: minimize batch-1 tail latency for dot-product heavy workloads by
// running short K-loops internally (single kick) instead of CPU issuing per-step ops.
//
// This module is intentionally Icarus-friendly and self-contained:
// - operands are staged via explicit load ports (modeling cache-coherent fills)
// - computation is a deterministic 1-word-per-cycle loop (4 INT8 MACs per cycle)
//
`timescale 1ns / 1ps

module attention_microkernel_engine #(
    parameter int unsigned XLEN      = 32,
    parameter int unsigned MAX_K     = 256,  // maximum dot length (elements)
    parameter int unsigned WORD_ELEMS = 4    // 4 int8 per 32-bit word
) (
    input  logic                   clk_i,
    input  logic                   rst_ni,

    // Configuration (latched on cfg_valid_i)
    input  logic                   cfg_valid_i,
    input  logic [$clog2(MAX_K+1)-1:0] cfg_k_i,        // number of int8 elements (multiple of 4 recommended)
    input  logic signed [15:0]      cfg_scale_i,       // fixed-point multiplier (Q8.8 style)
    input  logic [3:0]             cfg_shift_i,       // right shift after scaling
    input  logic signed [31:0]      cfg_clip_min_i,
    input  logic signed [31:0]      cfg_clip_max_i,
    input  logic                   cfg_enable_scale_i,
    input  logic                   cfg_enable_clip_i,

    // Operand staging (packed 4x int8 per 32-bit word)
    input  logic                   load_q_valid_i,
    input  logic [$clog2((MAX_K+WORD_ELEMS-1)/WORD_ELEMS)-1:0] load_q_idx_i,
    input  logic [31:0]            load_q_word_i,

    input  logic                   load_k_valid_i,
    input  logic [$clog2((MAX_K+WORD_ELEMS-1)/WORD_ELEMS)-1:0] load_k_idx_i,
    input  logic [31:0]            load_k_word_i,

    // Execute
    input  logic                   start_i,
    output logic                   busy_o,
    output logic                   done_o,

    // Result
    output logic                   result_valid_o,
    output logic signed [31:0]      result_o
);

  localparam int unsigned MAX_WORDS = (MAX_K + WORD_ELEMS - 1) / WORD_ELEMS;
  localparam int unsigned WORD_W    = $clog2(MAX_WORDS);

  // Staging RAMs (modeled as regs/arrays for simulation simplicity)
  logic [31:0] q_words [0:MAX_WORDS-1];
  logic [31:0] k_words [0:MAX_WORDS-1];

  // Latched config
  logic [$clog2(MAX_K+1)-1:0] k_q;
  logic signed [15:0]         scale_q;
  logic [3:0]                 shift_q;
  logic signed [31:0]         clip_min_q, clip_max_q;
  logic                       en_scale_q, en_clip_q;

  // Engine state
  typedef enum logic [1:0] {IDLE, RUN, FINALIZE} state_t;
  state_t state_q, state_d;

  logic [WORD_W-1:0] word_idx_q, word_idx_d;
  logic [WORD_W-1:0] k_words_q;

  logic signed [31:0] acc_q, acc_d;
  logic signed [31:0] dot4;

  // Helpers: unpack 4 bytes and compute dot of 4 int8 pairs
  function automatic logic signed [7:0] s8(input logic [7:0] b);
    s8 = $signed(b);
  endfunction

  // Icarus-friendly: avoid part-selects directly on memory words inside always_comb.
  always @(*) begin
    logic [31:0] qw;
    logic [31:0] kw;
    qw = q_words[word_idx_q];
    kw = k_words[word_idx_q];
    dot4 =
      ($signed(s8(qw[7:0]))   * $signed(s8(kw[7:0])))   +
      ($signed(s8(qw[15:8]))  * $signed(s8(kw[15:8])))  +
      ($signed(s8(qw[23:16])) * $signed(s8(kw[23:16]))) +
      ($signed(s8(qw[31:24])) * $signed(s8(kw[31:24])));
  end

  // Derive number of words from k_q (ceil(k/4))
  always_comb begin
    k_words_q = WORD_W'((k_q + (WORD_ELEMS-1)) / WORD_ELEMS);
  end

  // Default outputs
  always_comb begin
    state_d = state_q;
    word_idx_d = word_idx_q;
    acc_d = acc_q;

    busy_o = (state_q != IDLE);
    done_o = 1'b0;
    result_valid_o = 1'b0;
    result_o = '0;

    case (state_q)
      IDLE: begin
        acc_d = '0;
        word_idx_d = '0;
        if (start_i) begin
          state_d = RUN;
        end
      end

      RUN: begin
        // 1 word per cycle (4 multiplies) deterministic loop
        acc_d = acc_q + dot4;
        if (word_idx_q == (k_words_q - 1)) begin
          state_d = FINALIZE;
        end else begin
          word_idx_d = word_idx_q + 1;
        end
      end

      FINALIZE: begin
        logic signed [31:0] tmp;
        tmp = acc_q;

        if (en_scale_q) begin
          // Fixed-point: (acc * scale) >> shift
          // scale is signed Q8.8 by convention; shift adds extra right shift.
          logic signed [47:0] prod;
          prod = $signed(tmp) * $signed(scale_q); // 32x16 -> 48
          tmp = $signed(prod >>> (8 + shift_q));
        end

        if (en_clip_q) begin
          if (tmp > clip_max_q) tmp = clip_max_q;
          else if (tmp < clip_min_q) tmp = clip_min_q;
        end

        result_o = tmp;
        result_valid_o = 1'b1;
        done_o = 1'b1;
        state_d = IDLE;
      end

      default: begin
        state_d = IDLE;
      end
    endcase
  end

  // Sequential
  integer i_init;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE;
      word_idx_q <= '0;
      acc_q <= '0;

      k_q <= '0;
      scale_q <= '0;
      shift_q <= '0;
      clip_min_q <= '0;
      clip_max_q <= '0;
      en_scale_q <= 1'b0;
      en_clip_q <= 1'b0;

      for (i_init = 0; i_init < MAX_WORDS; i_init = i_init + 1) begin
        q_words[i_init] <= '0;
        k_words[i_init] <= '0;
      end
    end else begin
      state_q <= state_d;
      word_idx_q <= word_idx_d;
      acc_q <= acc_d;

      // latch config
      if (cfg_valid_i) begin
        k_q <= cfg_k_i;
        scale_q <= cfg_scale_i;
        shift_q <= cfg_shift_i;
        clip_min_q <= cfg_clip_min_i;
        clip_max_q <= cfg_clip_max_i;
        en_scale_q <= cfg_enable_scale_i;
        en_clip_q <= cfg_enable_clip_i;
      end

      // operand staging writes
      if (load_q_valid_i) begin
        q_words[load_q_idx_i] <= load_q_word_i;
      end
      if (load_k_valid_i) begin
        k_words[load_k_idx_i] <= load_k_word_i;
      end
    end
  end

endmodule

