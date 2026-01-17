// On-Chip SRAM Buffer for Garuda Accelerator
// Stores weights and activations for multi-lane operations
// Phase 2.2 of Production Roadmap

module onchip_buffer #(
    parameter int unsigned DEPTH          = 4096,  // Number of 32-bit words (16KB for 4096)
    parameter int unsigned DATA_WIDTH     = 32,    // Data width per entry
    parameter int unsigned NUM_BANKS      = 2,     // Number of banks (for ping-pong)
    parameter int unsigned NUM_PORTS      = 2      // Read/Write ports
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,
    
    // Write port
    input  logic                        wr_en_i,
    input  logic [$clog2(DEPTH)-1:0]    wr_addr_i,
    input  logic [DATA_WIDTH-1:0]       wr_data_i,
    
    // Read port
    input  logic                        rd_en_i,
    input  logic [$clog2(DEPTH)-1:0]    rd_addr_i,
    output logic [DATA_WIDTH-1:0]       rd_data_o,
    
    // Bank selection (for ping-pong)
    input  logic [$clog2(NUM_BANKS)-1:0] bank_sel_i
);

  // Memory array (synthesized to BRAM on FPGA)
  logic [NUM_BANKS-1:0][DEPTH-1:0][DATA_WIDTH-1:0] memory;
  
  // Write logic
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      for (int bank = 0; bank < NUM_BANKS; bank++) begin
        for (int i = 0; i < DEPTH; i++) begin
          memory[bank][i] <= '0;
        end
      end
    end else if (wr_en_i) begin
      memory[bank_sel_i][wr_addr_i] <= wr_data_i;
    end
  end
  
  // Read logic (asynchronous read for better performance)
  assign rd_data_o = (rd_en_i) ? memory[bank_sel_i][rd_addr_i] : '0;
  
  // Note: For FPGA synthesis, this will be inferred as BRAM
  // For ASIC, would use dedicated SRAM compiler

endmodule
