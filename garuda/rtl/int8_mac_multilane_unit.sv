// INT8 MAC Multi-Lane Execution Unit
// Supports configurable parallelism: 16, 32, 64, or more MAC lanes
// Each lane performs independent 8×8 MAC operations in parallel

module int8_mac_multilane_unit
  import int8_mac_instr_pkg::*;
#(
    parameter int unsigned XLEN        = 32,
    parameter int unsigned NUM_LANES   = 16,  // Number of parallel MAC lanes (16, 32, 64, etc.)
    parameter int unsigned LANE_WIDTH  = 32,  // Width per lane (32-bit = 4 INT8s per lane)
    parameter type         opcode_t    = logic,
    parameter type         hartid_t    = logic,
    parameter type         id_t        = logic
) (
    input  logic                       clk_i,
    input  logic                       rst_ni,
    
    // Input operands: Wide data buses for multi-lane operations
    // For NUM_LANES=16, each lane processes 4 INT8s, so we need:
    // rs1/rs2: NUM_LANES * LANE_WIDTH bits = 16 * 32 = 512 bits
    input  logic [NUM_LANES*LANE_WIDTH-1:0] rs1_i,
    input  logic [NUM_LANES*LANE_WIDTH-1:0] rs2_i,
    input  logic [XLEN-1:0]                  rd_i,  // Single 32-bit accumulator
    
    input  opcode_t                      opcode_i,
    input  hartid_t                      hartid_i,
    input  id_t                          id_i,
    input  logic [4:0]                   rd_addr_i,
    
    output logic [XLEN-1:0]              result_o,
    output logic                         valid_o,
    output logic                         we_o,
    output logic [4:0]                   rd_addr_o,
    output hartid_t                      hartid_o,
    output id_t                          id_o,
    output logic                         overflow_o
);

  // Per-lane signals
  logic signed [7:0]  lane_rs1_bytes [NUM_LANES-1:0][3:0];
  logic signed [7:0]  lane_rs2_bytes [NUM_LANES-1:0][3:0];
  logic signed [15:0] lane_products [NUM_LANES-1:0][3:0];
  logic signed [31:0] lane_dot_products [NUM_LANES-1:0];
  logic signed [31:0] final_sum;

  // Scalar signals (for backward compatibility with scalar ops)
  logic signed [7:0]  a, b, acc_8bit;
  logic signed [15:0] product;
  logic signed [8:0]  sum_9bit;
  logic signed [31:0] sum_32bit;

  logic [XLEN-1:0] result_comb;
  logic            valid_comb, we_comb;
  logic            overflow_comb;
  
  logic [XLEN-1:0] result_q;
  logic            valid_q, we_q;
  logic            overflow_q;
  logic [4:0]      rd_addr_q;
  hartid_t         hartid_q;
  id_t             id_q;

  // Unpack input operands for each lane
  // Each lane gets LANE_WIDTH bits (32 bits = 4 INT8 values)
  always_comb begin
    for (int lane = 0; lane < NUM_LANES; lane++) begin
      logic [LANE_WIDTH-1:0] lane_rs1, lane_rs2;
      lane_rs1 = rs1_i[(lane+1)*LANE_WIDTH-1 : lane*LANE_WIDTH];
      lane_rs2 = rs2_i[(lane+1)*LANE_WIDTH-1 : lane*LANE_WIDTH];
      
      // Unpack 4 INT8 values per lane
      lane_rs1_bytes[lane][0] = lane_rs1[7:0];
      lane_rs1_bytes[lane][1] = lane_rs1[15:8];
      lane_rs1_bytes[lane][2] = lane_rs1[23:16];
      lane_rs1_bytes[lane][3] = lane_rs1[31:24];
      
      lane_rs2_bytes[lane][0] = lane_rs2[7:0];
      lane_rs2_bytes[lane][1] = lane_rs2[15:8];
      lane_rs2_bytes[lane][2] = lane_rs2[23:16];
      lane_rs2_bytes[lane][3] = lane_rs2[31:24];
      
      // Compute 4 multiplications per lane
      for (int i = 0; i < 4; i++) begin
        lane_products[lane][i] = lane_rs1_bytes[lane][i] * lane_rs2_bytes[lane][i];
      end
      
      // Sum 4 products per lane (lane dot product)
      lane_dot_products[lane] = $signed(lane_products[lane][0]) + 
                                $signed(lane_products[lane][1]) + 
                                $signed(lane_products[lane][2]) + 
                                $signed(lane_products[lane][3]);
    end
  end
  
  // Sum all lane dot products + accumulator
  // This creates a tree of adders for better timing
  always_comb begin
    logic signed [31:0] intermediate_sums [(NUM_LANES+1)/2-1:0];
    
    // First level: Pair-wise addition
    for (int i = 0; i < NUM_LANES/2; i++) begin
      intermediate_sums[i] = lane_dot_products[2*i] + lane_dot_products[2*i+1];
    end
    
    // If odd number of lanes, pass through last one
    if (NUM_LANES % 2) begin
      intermediate_sums[NUM_LANES/2] = lane_dot_products[NUM_LANES-1];
    end
    
    // Recursive tree reduction (simplified for synthesis)
    // In real implementation, would use a proper tree structure
    final_sum = rd_i;
    for (int i = 0; i < (NUM_LANES+1)/2; i++) begin
      final_sum = final_sum + intermediate_sums[i];
    end
  end

  // Scalar operations (backward compatible with existing instructions)
  assign a = rs1_i[7:0];
  assign b = rs2_i[7:0];
  assign acc_8bit = rd_i[7:0];
  
  assign product = a * b;
  assign sum_9bit = $signed({product[7], product[7:0]}) + $signed({acc_8bit[7], acc_8bit});
  assign sum_32bit = $signed({{16{product[15]}}, product}) + $signed(rd_i);

  // Instruction decoding and result computation
  always_comb begin
    result_comb = '0;
    valid_comb  = 1'b0;
    we_comb     = 1'b0;
    overflow_comb = 1'b0;
    
    case (opcode_i)
      MAC8: begin
        if (sum_9bit > 9'sd127) begin
          result_comb = {{24{1'b0}}, 8'sd127};
          overflow_comb = 1'b1;
        end else if (sum_9bit < -9'sd128) begin
          result_comb = {{24{1'b1}}, -8'sd128};
          overflow_comb = 1'b1;
        end else begin
          result_comb = {{24{sum_9bit[7]}}, sum_9bit[7:0]};
          overflow_comb = 1'b0;
        end
        valid_comb = 1'b1;
        we_comb    = 1'b1;
      end
      
      MAC8_ACC: begin
        result_comb = sum_32bit;
        valid_comb  = 1'b1;
        we_comb     = 1'b1;
      end
      
      MUL8: begin
        result_comb = {{16{product[15]}}, product};
        valid_comb  = 1'b1;
        we_comb     = 1'b1;
      end
      
      CLIP8: begin
        if ($signed(rs1_i[XLEN-1:0]) > 32'sd127) begin
          result_comb = {{24{1'b0}}, 8'sd127};
          overflow_comb = 1'b1;
        end else if ($signed(rs1_i[XLEN-1:0]) < -32'sd128) begin
          result_comb = {{24{1'b1}}, -8'sd128};
          overflow_comb = 1'b1;
        end else begin
          result_comb = {{24{rs1_i[7]}}, rs1_i[7:0]};
          overflow_comb = 1'b0;
        end
        valid_comb = 1'b1;
        we_comb    = 1'b1;
      end

      SIMD_DOT: begin
        // Multi-lane SIMD_DOT: Processes NUM_LANES * 4 = total MAC operations
        // e.g., 16 lanes × 4 MACs/lane = 64 MAC operations per cycle
        result_comb = final_sum;
        valid_comb  = 1'b1;
        we_comb     = 1'b1;
        overflow_comb = 1'b0;  // Could add overflow detection for large sums
      end
      
      default: begin
        result_comb = '0;
        valid_comb  = 1'b0;
        we_comb     = 1'b0;
      end
    endcase
  end
  
  // Pipeline register
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      result_q   <= '0;
      valid_q    <= '0;
      we_q       <= '0;
      overflow_q <= '0;
      rd_addr_q  <= '0;
      hartid_q   <= '0;
      id_q       <= '0;
    end else begin
      result_q   <= result_comb;
      valid_q    <= valid_comb;
      we_q       <= we_comb;
      overflow_q <= overflow_comb;
      rd_addr_q  <= rd_addr_i;
      hartid_q   <= hartid_i;
      id_q       <= id_i;
    end
  end
  
  assign result_o   = result_q;
  assign valid_o    = valid_q;
  assign we_o       = we_q;
  assign overflow_o = overflow_q;
  assign rd_addr_o  = rd_addr_q;
  assign hartid_o   = hartid_q;
  assign id_o       = id_q;
  
  // Assertions for verification
  `ifndef SYNTHESIS
  property p_valid_opcode;
    @(posedge clk_i) disable iff (!rst_ni)
    (opcode_i inside {MAC8, MAC8_ACC, MUL8, CLIP8, SIMD_DOT, ILLEGAL});
  endproperty
  assert property (p_valid_opcode) else $error("Invalid opcode received");
  
  property p_valid_implies_we;
    @(posedge clk_i) disable iff (!rst_ni)
    (valid_o |-> we_o);
  endproperty
  assert property (p_valid_implies_we) else $error("Valid output without writeback");
  
  cover property (@(posedge clk_i) overflow_o);
  `endif

endmodule
