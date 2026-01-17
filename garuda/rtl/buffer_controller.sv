// Buffer Controller - Manages Weight, Activation, and Accumulator Buffers
// Phase 2.2 of Production Roadmap
// Coordinates buffer access, DMA routing, and multi-lane unit data flow

module buffer_controller #(
    parameter int unsigned NUM_LANES      = 16,
    parameter int unsigned LANE_WIDTH     = 32,
    parameter int unsigned DATA_WIDTH     = 32,
    parameter int unsigned ADDR_WIDTH     = 32,
    
    // Buffer sizes
    parameter int unsigned WEIGHT_DEPTH   = 32768,   // 128KB
    parameter int unsigned ACT_DEPTH      = 16384,   // 64KB per bank
    parameter int unsigned ACC_DEPTH      = 8192     // 32KB
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,
    
    // DMA interface (write to buffers)
    input  logic                        dma_wr_valid_i,
    input  logic [ADDR_WIDTH-1:0]       dma_wr_addr_i,
    input  logic [DATA_WIDTH-1:0]       dma_wr_data_i,
    output logic                        dma_wr_ready_o,
    
    // Buffer selection (from DMA address space)
    // 0x0000_0000 - 0x0001_FFFF: Weight buffer (128KB)
    // 0x0002_0000 - 0x0002_FFFF: Activation ping (64KB)
    // 0x0003_0000 - 0x0003_FFFF: Activation pong (64KB)
    // 0x0004_0000 - 0x0004_7FFF: Accumulator buffer (32KB)
    
    // Multi-lane unit interface (read from buffers)
    // Weight access
    output logic [NUM_LANES-1:0]        weight_rd_en_o,
    output logic [NUM_LANES-1:0][$clog2(WEIGHT_DEPTH)-1:0] weight_rd_addr_o,
    input  logic [NUM_LANES-1:0][DATA_WIDTH-1:0] weight_rd_data_i,
    input  logic [NUM_LANES-1:0]        weight_rd_valid_i,
    
    // Activation access (wide read)
    input  logic                        act_rd_en_i,
    input  logic [$clog2(ACT_DEPTH)-1:0] act_rd_addr_i,
    output logic [NUM_LANES*LANE_WIDTH-1:0] act_rd_data_o,
    output logic                        act_rd_valid_o,
    
    // Accumulator access (read-modify-write for MAC)
    input  logic                        acc_rmw_en_i,
    input  logic [$clog2(ACC_DEPTH)-1:0] acc_rmw_addr_i,
    input  logic [DATA_WIDTH-1:0]       acc_rmw_data_i,
    output logic [DATA_WIDTH-1:0]       acc_rmw_result_o,
    output logic                        acc_rmw_ready_o,
    
    // Ping-pong control for activation buffer
    input  logic                        ping_pong_sel_i,  // 0 = ping, 1 = pong
    output logic                        ping_pong_swap_o  // Swap request
);

  // Address decoding for DMA writes
  logic [$clog2(WEIGHT_DEPTH)-1:0] weight_wr_addr;
  logic [$clog2(ACT_DEPTH)-1:0]    act_wr_addr;
  logic [$clog2(ACC_DEPTH)-1:0]    acc_wr_addr;
  
  logic weight_wr_en, act_wr_en, acc_wr_en;
  logic weight_wr_ready, act_wr_ready, acc_wr_ready;
  
  // Decode DMA address to buffer selection
  always_comb begin
    weight_wr_en = 1'b0;
    act_wr_en = 1'b0;
    acc_wr_en = 1'b0;
    weight_wr_addr = '0;
    act_wr_addr = '0;
    acc_wr_addr = '0;
    dma_wr_ready_o = 1'b0;
    
    if (dma_wr_valid_i) begin
      // Weight buffer: 0x0000_0000 - 0x0001_FFFF (128KB)
      if (dma_wr_addr_i[19:17] == 3'b000) begin
        weight_wr_en = 1'b1;
        weight_wr_addr = dma_wr_addr_i[$clog2(WEIGHT_DEPTH)-1:0];
        dma_wr_ready_o = weight_wr_ready;
      end
      // Activation ping: 0x0002_0000 - 0x0002_FFFF (64KB)
      else if (dma_wr_addr_i[19:16] == 4'b0010) begin
        act_wr_en = 1'b1;
        act_wr_addr = dma_wr_addr_i[$clog2(ACT_DEPTH)-1:0];
        dma_wr_ready_o = act_wr_ready;
      end
      // Activation pong: 0x0003_0000 - 0x0003_FFFF (64KB)
      else if (dma_wr_addr_i[19:16] == 4'b0011) begin
        act_wr_en = 1'b1;
        act_wr_addr = dma_wr_addr_i[$clog2(ACT_DEPTH)-1:0];
        dma_wr_ready_o = act_wr_ready;
      end
      // Accumulator: 0x0004_0000 - 0x0004_7FFF (32KB)
      else if (dma_wr_addr_i[19:15] == 5'b00100) begin
        acc_wr_en = 1'b1;
        acc_wr_addr = dma_wr_addr_i[$clog2(ACC_DEPTH)-1:0];
        dma_wr_ready_o = acc_wr_ready;
      end
    end
  end
  
  // Instantiate buffers
  // Weight buffer (not shown - would instantiate here)
  // Activation buffer (not shown - would instantiate here)
  // Accumulator buffer (not shown - would instantiate here)
  
  // For now, pass through signals
  // Full integration would instantiate actual buffer modules
  
  assign weight_wr_ready = 1'b1;  // Placeholder
  assign act_wr_ready = 1'b1;     // Placeholder
  assign acc_wr_ready = 1'b1;     // Placeholder
  
  // Activation read (wide)
  // Would connect to activation_buffer wide_rd_data_o
  assign act_rd_data_o = '0;
  assign act_rd_valid_o = 1'b0;
  
  // Accumulator read-modify-write
  // Would connect to accumulator_buffer rmw_result_o
  assign acc_rmw_result_o = '0;
  assign acc_rmw_ready_o = 1'b0;
  
  // Ping-pong swap (can be triggered by software or hardware)
  assign ping_pong_swap_o = 1'b0;  // Placeholder

endmodule
