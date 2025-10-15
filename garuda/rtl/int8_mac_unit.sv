// INT8 MAC execution unit
// Performs multiply-accumulate and saturation operations on INT8 data

module int8_mac_unit
  import int8_mac_instr_pkg::*;
#(
    parameter int unsigned XLEN     = 32,
    parameter type         opcode_t = logic,
    parameter type         hartid_t = logic,
    parameter type         id_t     = logic
) (
    input  logic                  clk_i,
    input  logic                  rst_ni,
    
    input  logic [XLEN-1:0]       rs1_i,
    input  logic [XLEN-1:0]       rs2_i,
    input  logic [XLEN-1:0]       rd_i,
    input  opcode_t               opcode_i,
    input  hartid_t               hartid_i,
    input  id_t                   id_i,
    input  logic [4:0]            rd_addr_i,
    
    output logic [XLEN-1:0]       result_o,
    output logic                  valid_o,
    output logic                  we_o,
    output logic [4:0]            rd_addr_o,
    output hartid_t               hartid_o,
    output id_t                   id_o,
    output logic                  overflow_o      // Saturation occurred flag
);

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

  assign a = rs1_i[7:0];
  assign b = rs2_i[7:0];
  assign acc_8bit = rd_i[7:0];
  
  assign product = a * b;
  assign sum_9bit = $signed({product[7], product[7:0]}) + $signed({acc_8bit[7], acc_8bit});
  assign sum_32bit = $signed({{16{product[15]}}, product}) + $signed(rd_i);
  
  always_comb begin
    result_comb = '0;
    valid_comb  = 1'b0;
    we_comb     = 1'b0;
    overflow_comb = 1'b0;
    
    case (opcode_i)
      MAC8: begin
        if (sum_9bit > 9'sd127) begin
          result_comb = {{24{1'b0}}, 8'sd127};
          overflow_comb = 1'b1;  // Positive overflow
        end else if (sum_9bit < -9'sd128) begin
          result_comb = {{24{1'b1}}, -8'sd128};  // Fix: -128 in two's complement
          overflow_comb = 1'b1;  // Negative overflow
        end else begin
          result_comb = {{24{sum_9bit[7]}}, sum_9bit[7:0]};
          overflow_comb = 1'b0;  // No overflow
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
        if ($signed(rs1_i) > 32'sd127) begin
          result_comb = {{24{1'b0}}, 8'sd127};
          overflow_comb = 1'b1;  // Clipped to max
        end else if ($signed(rs1_i) < -32'sd128) begin
          result_comb = {{24{1'b1}}, -8'sd128};  // Fix: -128 in two's complement
          overflow_comb = 1'b1;  // Clipped to min
        end else begin
          result_comb = {{24{rs1_i[7]}}, rs1_i[7:0]};
          overflow_comb = 1'b0;  // No clipping
        end
        valid_comb = 1'b1;
        we_comb    = 1'b1;
      end
      
      default: begin
        result_comb = '0;
        valid_comb  = 1'b0;
        we_comb     = 1'b0;
      end
    endcase
  end
  
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
  // Check that opcode is valid
  property p_valid_opcode;
    @(posedge clk_i) disable iff (!rst_ni)
    (opcode_i inside {MAC8, MAC8_ACC, MUL8, CLIP8, ILLEGAL});
  endproperty
  assert property (p_valid_opcode) else $error("Invalid opcode received");
  
  // Check that valid implies writeback
  property p_valid_implies_we;
    @(posedge clk_i) disable iff (!rst_ni)
    (valid_o |-> we_o);
  endproperty
  assert property (p_valid_implies_we) else $error("Valid output without writeback");
  
  // Coverage: Track overflow events
  cover property (@(posedge clk_i) overflow_o);
  `endif

endmodule
