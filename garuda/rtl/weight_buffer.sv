// Weight Buffer - 128KB SRAM for Filter Weights
// Phase 2.2 of Production Roadmap
// Stores filter weights for convolutional layers

module weight_buffer #(
    parameter int unsigned DEPTH          = 32768,  // 128KB = 32768 × 32 bits
    parameter int unsigned DATA_WIDTH     = 32,     // 32-bit words
    parameter int unsigned NUM_BANKS      = 4,      // 4 banks for parallel access
    parameter int unsigned ADDR_WIDTH     = 15      // log2(32768) = 15
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,
    
    // Write port (DMA/CPU)
    input  logic                        wr_en_i,
    input  logic [ADDR_WIDTH-1:0]       wr_addr_i,
    input  logic [DATA_WIDTH-1:0]       wr_data_i,
    output logic                        wr_ready_o,
    
    // Read ports (parallel access for multi-lane)
    input  logic [NUM_BANKS-1:0]        rd_en_i,
    input  logic [NUM_BANKS-1:0][ADDR_WIDTH-1:0] rd_addr_i,
    output logic [NUM_BANKS-1:0][DATA_WIDTH-1:0] rd_data_o,
    output logic [NUM_BANKS-1:0]        rd_valid_o
);

  // Memory array - synthesized to BRAM on FPGA
  // Each bank is 32KB (8192 × 32 bits)
  localparam int unsigned BANK_DEPTH = DEPTH / NUM_BANKS;
  
  logic [NUM_BANKS-1:0][BANK_DEPTH-1:0][DATA_WIDTH-1:0] memory;
  
  // Bank selection for writes
  logic [$clog2(NUM_BANKS)-1:0] wr_bank;
  logic [ADDR_WIDTH-$clog2(NUM_BANKS)-1:0] wr_bank_addr;
  
  assign wr_bank = wr_addr_i[ADDR_WIDTH-1 : ADDR_WIDTH-$clog2(NUM_BANKS)];
  assign wr_bank_addr = wr_addr_i[ADDR_WIDTH-$clog2(NUM_BANKS)-1 : 0];
  
  // Write logic (single port)
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      for (int bank = 0; bank < NUM_BANKS; bank++) begin
        for (int i = 0; i < BANK_DEPTH; i++) begin
          memory[bank][i] <= '0;
        end
      end
      wr_ready_o <= 1'b0;
    end else begin
      wr_ready_o <= 1'b0;
      if (wr_en_i) begin
        if (wr_bank_addr < BANK_DEPTH) begin
          memory[wr_bank][wr_bank_addr] <= wr_data_i;
          wr_ready_o <= 1'b1;
        end
      end
    end
  end
  
  // Read logic (parallel ports, one per bank)
  always_comb begin
    for (int bank = 0; bank < NUM_BANKS; bank++) begin
      logic [$clog2(NUM_BANKS)-1:0] rd_bank;
      logic [ADDR_WIDTH-$clog2(NUM_BANKS)-1:0] rd_bank_addr;
      
      rd_bank = rd_addr_i[bank][ADDR_WIDTH-1 : ADDR_WIDTH-$clog2(NUM_BANKS)];
      rd_bank_addr = rd_addr_i[bank][ADDR_WIDTH-$clog2(NUM_BANKS)-1 : 0];
      
      if (rd_en_i[bank] && rd_bank == bank && rd_bank_addr < BANK_DEPTH) begin
        rd_data_o[bank] = memory[bank][rd_bank_addr];
        rd_valid_o[bank] = 1'b1;
      end else begin
        rd_data_o[bank] = '0;
        rd_valid_o[bank] = 1'b0;
      end
    end
  end
  
  // Note: For FPGA synthesis, each bank will be inferred as separate BRAM
  // For ASIC, would use dedicated SRAM compiler

endmodule
