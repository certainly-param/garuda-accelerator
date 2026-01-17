// Activation Buffer - 64KB SRAM with Ping-Pong Double Buffering
// Phase 2.2 of Production Roadmap
// Double-buffered for ping-pong access: one buffer reads while other writes

module activation_buffer #(
    parameter int unsigned DEPTH          = 16384,  // 64KB = 16384 × 32 bits per bank
    parameter int unsigned DATA_WIDTH     = 32,     // 32-bit words
    parameter int unsigned NUM_BANKS      = 2,      // Ping-pong: 2 banks
    parameter int unsigned ADDR_WIDTH     = 14      // log2(16384) = 14
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,
    
    // Bank selection for ping-pong
    input  logic                        ping_pong_sel_i,  // 0 = ping, 1 = pong
    
    // Write port (DMA/CPU)
    input  logic                        wr_en_i,
    input  logic [ADDR_WIDTH-1:0]       wr_addr_i,
    input  logic [DATA_WIDTH-1:0]       wr_data_i,
    output logic                        wr_ready_o,
    
    // Read port (multi-lane unit)
    input  logic                        rd_en_i,
    input  logic [ADDR_WIDTH-1:0]       rd_addr_i,
    output logic [DATA_WIDTH-1:0]       rd_data_o,
    output logic                        rd_valid_o,
    
    // Wide read port (for multi-lane: NUM_LANES words at once)
    parameter int unsigned NUM_LANES     = 16,
    parameter int unsigned LANE_WIDTH    = 32,
    input  logic                        wide_rd_en_i,
    input  logic [ADDR_WIDTH-1:0]       wide_rd_addr_i,
    output logic [NUM_LANES*LANE_WIDTH-1:0] wide_rd_data_o,
    output logic                        wide_rd_valid_o
);

  // Memory array - ping-pong banks
  logic [NUM_BANKS-1:0][DEPTH-1:0][DATA_WIDTH-1:0] memory;
  
  // Write bank selection
  logic [$clog2(NUM_BANKS)-1:0] wr_bank;
  
  assign wr_bank = ping_pong_sel_i;  // Write to selected bank
  
  // Read bank selection (opposite of write for ping-pong)
  logic [$clog2(NUM_BANKS)-1:0] rd_bank;
  
  assign rd_bank = ~ping_pong_sel_i;  // Read from opposite bank
  
  // Write logic
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      for (int bank = 0; bank < NUM_BANKS; bank++) begin
        for (int i = 0; i < DEPTH; i++) begin
          memory[bank][i] <= '0;
        end
      end
      wr_ready_o <= 1'b0;
    end else begin
      wr_ready_o <= 1'b0;
      if (wr_en_i && wr_addr_i < DEPTH) begin
        memory[wr_bank][wr_addr_i] <= wr_data_i;
        wr_ready_o <= 1'b1;
      end
    end
  end
  
  // Standard read port
  always_comb begin
    rd_data_o = '0;
    rd_valid_o = 1'b0;
    
    if (rd_en_i && rd_addr_i < DEPTH) begin
      rd_data_o = memory[rd_bank][rd_addr_i];
      rd_valid_o = 1'b1;
    end
  end
  
  // Wide read port (for multi-lane: reads NUM_LANES consecutive words)
  always_comb begin
    wide_rd_data_o = '0;
    wide_rd_valid_o = 1'b0;
    
    if (wide_rd_en_i && wide_rd_addr_i + NUM_LANES <= DEPTH) begin
      // Read NUM_LANES consecutive words starting from wide_rd_addr_i
      for (int i = 0; i < NUM_LANES; i++) begin
        logic [ADDR_WIDTH-1:0] addr;
        addr = wide_rd_addr_i + i;
        wide_rd_data_o[i*LANE_WIDTH +: LANE_WIDTH] = memory[rd_bank][addr];
      end
      wide_rd_valid_o = 1'b1;
    end
  end
  
  // Note: For FPGA synthesis, each bank will be inferred as BRAM
  // Ping-pong allows: write to bank 0 while reading from bank 1 (and vice versa)

endmodule
