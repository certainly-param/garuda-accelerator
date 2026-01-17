// Accumulator Buffer - 32KB SRAM for Intermediate Results
// Phase 2.2 of Production Roadmap
// Stores partial sums and intermediate MAC results

module accumulator_buffer #(
    parameter int unsigned DEPTH          = 8192,   // 32KB = 8192 × 32 bits
    parameter int unsigned DATA_WIDTH     = 32,     // 32-bit accumulators
    parameter int unsigned ADDR_WIDTH     = 13      // log2(8192) = 13
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,
    
    // Read-modify-write port (for MAC accumulation)
    input  logic                        rmw_en_i,
    input  logic [ADDR_WIDTH-1:0]       rmw_addr_i,
    input  logic [DATA_WIDTH-1:0]       rmw_data_i,     // Data to add
    output logic [DATA_WIDTH-1:0]       rmw_result_o,   // Old value before update
    output logic                        rmw_ready_o,
    
    // Write port (for initialization/reset)
    input  logic                        wr_en_i,
    input  logic [ADDR_WIDTH-1:0]       wr_addr_i,
    input  logic [DATA_WIDTH-1:0]       wr_data_i,
    output logic                        wr_ready_o,
    
    // Read port (for final results)
    input  logic                        rd_en_i,
    input  logic [ADDR_WIDTH-1:0]       rd_addr_i,
    output logic [DATA_WIDTH-1:0]       rd_data_o,
    output logic                        rd_valid_o,
    
    // Wide read port (for multi-lane: reads NUM_LANES words)
    parameter int unsigned NUM_LANES     = 16,
    parameter int unsigned LANE_WIDTH    = 32,
    input  logic                        wide_rd_en_i,
    input  logic [ADDR_WIDTH-1:0]       wide_rd_addr_i,
    output logic [NUM_LANES*LANE_WIDTH-1:0] wide_rd_data_o,
    output logic                        wide_rd_valid_o
);

  // Memory array
  logic [DEPTH-1:0][DATA_WIDTH-1:0] memory;
  
  // Read-modify-write logic (for MAC: result = old + new)
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      for (int i = 0; i < DEPTH; i++) begin
        memory[i] <= '0;
      end
      rmw_ready_o <= 1'b0;
      wr_ready_o <= 1'b0;
    end else begin
      rmw_ready_o <= 1'b0;
      wr_ready_o <= 1'b0;
      
      // Read-modify-write (MAC accumulation)
      if (rmw_en_i && rmw_addr_i < DEPTH) begin
        rmw_result_o <= memory[rmw_addr_i];  // Return old value
        memory[rmw_addr_i] <= memory[rmw_addr_i] + rmw_data_i;  // Accumulate
        rmw_ready_o <= 1'b1;
      end
      
      // Write (for initialization)
      if (wr_en_i && wr_addr_i < DEPTH) begin
        memory[wr_addr_i] <= wr_data_i;
        wr_ready_o <= 1'b1;
      end
    end
  end
  
  // Read port
  always_comb begin
    rd_data_o = '0;
    rd_valid_o = 1'b0;
    
    if (rd_en_i && rd_addr_i < DEPTH) begin
      rd_data_o = memory[rd_addr_i];
      rd_valid_o = 1'b1;
    end
  end
  
  // Wide read port (for multi-lane)
  always_comb begin
    wide_rd_data_o = '0;
    wide_rd_valid_o = 1'b0;
    
    if (wide_rd_en_i && wide_rd_addr_i + NUM_LANES <= DEPTH) begin
      for (int i = 0; i < NUM_LANES; i++) begin
        logic [ADDR_WIDTH-1:0] addr;
        addr = wide_rd_addr_i + i;
        wide_rd_data_o[i*LANE_WIDTH +: LANE_WIDTH] = memory[addr];
      end
      wide_rd_valid_o = 1'b1;
    end
  end
  
  // Note: Read-modify-write port is optimized for MAC operations
  // where we read old value, add new value, write back

endmodule
