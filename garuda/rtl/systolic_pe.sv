// Systolic Processing Element (PE) - Basic building block for systolic array
// Phase 4.1 Enhancement: 2D Systolic Array
// Single PE with MAC operation and data flow

module systolic_pe #(
    parameter int unsigned DATA_WIDTH = 8,    // INT8 data width
    parameter int unsigned ACC_WIDTH  = 32,   // Accumulator width
    parameter int unsigned PE_ID      = 0     // PE identifier (for debugging)
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,
    
    // Data flow: systolic inputs/outputs
    input  logic [DATA_WIDTH-1:0]       weight_i,        // Weight from north (row)
    input  logic [DATA_WIDTH-1:0]       activation_i,    // Activation from west (column)
    input  logic [ACC_WIDTH-1:0]        partial_sum_i,   // Partial sum from north
    output logic [DATA_WIDTH-1:0]       weight_o,        // Pass weight to south
    output logic [DATA_WIDTH-1:0]       activation_o,    // Pass activation to east
    output logic [ACC_WIDTH-1:0]        partial_sum_o,   // Pass partial sum to south
    
    // Control
    input  logic                        weight_load_i,   // Load weight into PE
    input  logic                        accumulate_en_i, // Enable accumulation
    input  logic                        clear_acc_i      // Clear accumulator
);

  // Internal registers
  logic [DATA_WIDTH-1:0] weight_reg_q, weight_reg_d;
  logic [ACC_WIDTH-1:0]  accumulator_q, accumulator_d;
  
  // Multiply: weight × activation
  logic [2*DATA_WIDTH-1:0] product;
  
  // Multiply-accumulate operation
  assign product = $signed(weight_reg_q) * $signed(activation_i);
  
  // Accumulator update
  always_comb begin
    accumulator_d = accumulator_q;
    
    if (!rst_ni || clear_acc_i) begin
      accumulator_d = '0;
    end else if (accumulate_en_i) begin
      // MAC: accumulator = accumulator + (weight × activation) + partial_sum
      accumulator_d = accumulator_q + $signed(product) + $signed(partial_sum_i);
    end
  end
  
  // Weight register (loadable)
  always_comb begin
    weight_reg_d = weight_reg_q;
    
    if (weight_load_i) begin
      weight_reg_d = weight_i;  // Load weight from north
    end
  end
  
  // Systolic data flow (pass-through with optional processing)
  assign weight_o = weight_i;           // Pass weight south (row-wise)
  assign activation_o = activation_i;   // Pass activation east (column-wise)
  assign partial_sum_o = accumulator_q; // Output partial sum south
  
  // Sequential logic
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      weight_reg_q <= '0;
      accumulator_q <= '0;
    end else begin
      weight_reg_q <= weight_reg_d;
      accumulator_q <= accumulator_d;
    end
  end

endmodule
