// Buffer Subsystem - Integrated Weight, Activation, and Accumulator Buffers
// Phase 2.2 of Production Roadmap
// Complete buffer hierarchy with DMA routing and multi-lane access

module buffer_subsystem #(
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
    
    // Multi-lane unit: Weight access (parallel reads)
    input  logic [NUM_LANES-1:0]        weight_rd_en_i,
    input  logic [NUM_LANES-1:0][$clog2(WEIGHT_DEPTH)-1:0] weight_rd_addr_i,
    output logic [NUM_LANES-1:0][DATA_WIDTH-1:0] weight_rd_data_o,
    output logic [NUM_LANES-1:0]        weight_rd_valid_o,
    
    // Multi-lane unit: Activation access (wide read)
    input  logic                        act_rd_en_i,
    input  logic [$clog2(ACT_DEPTH)-1:0] act_rd_addr_i,
    output logic [NUM_LANES*LANE_WIDTH-1:0] act_rd_data_o,
    output logic                        act_rd_valid_o,
    
    // Multi-lane unit: Accumulator access (read-modify-write)
    input  logic                        acc_rmw_en_i,
    input  logic [$clog2(ACC_DEPTH)-1:0] acc_rmw_addr_i,
    input  logic [DATA_WIDTH-1:0]       acc_rmw_data_i,
    output logic [DATA_WIDTH-1:0]       acc_rmw_result_o,
    output logic                        acc_rmw_ready_o,
    
    // Ping-pong control for activation buffer
    input  logic                        ping_pong_sel_i  // 0 = ping, 1 = pong
);

  // Address decoding for DMA writes
  logic weight_wr_en, act_wr_en, acc_wr_en;
  logic [$clog2(WEIGHT_DEPTH)-1:0] weight_wr_addr;
  logic [$clog2(ACT_DEPTH)-1:0]    act_wr_addr;
  logic [$clog2(ACC_DEPTH)-1:0]    acc_wr_addr;
  
  logic weight_wr_ready, act_wr_ready, acc_wr_ready;
  
  // Decode DMA address to buffer selection
  // Address mapping:
  // 0x0000_0000 - 0x0001_FFFF: Weight buffer (128KB)
  // 0x0002_0000 - 0x0002_FFFF: Activation ping (64KB)
  // 0x0003_0000 - 0x0003_FFFF: Activation pong (64KB)
  // 0x0004_0000 - 0x0004_7FFF: Accumulator buffer (32KB)
  
  always_comb begin
    weight_wr_en = 1'b0;
    act_wr_en = 1'b0;
    acc_wr_en = 1'b0;
    weight_wr_addr = '0;
    act_wr_addr = '0;
    acc_wr_addr = '0;
    dma_wr_ready_o = 1'b0;
    
    if (dma_wr_valid_i) begin
      // Weight buffer: 0x0000_0000 - 0x0001_FFFF
      if (dma_wr_addr_i[19:17] == 3'b000) begin
        weight_wr_en = 1'b1;
        weight_wr_addr = dma_wr_addr_i[$clog2(WEIGHT_DEPTH)-1:0];
        dma_wr_ready_o = weight_wr_ready;
      end
      // Activation ping: 0x0002_0000 - 0x0002_FFFF
      else if (dma_wr_addr_i[19:16] == 4'b0010) begin
        act_wr_en = 1'b1;
        act_wr_addr = dma_wr_addr_i[$clog2(ACT_DEPTH)-1:0];
        dma_wr_ready_o = act_wr_ready;
      end
      // Activation pong: 0x0003_0000 - 0x0003_FFFF
      else if (dma_wr_addr_i[19:16] == 4'b0011) begin
        act_wr_en = 1'b1;
        act_wr_addr = dma_wr_addr_i[$clog2(ACT_DEPTH)-1:0];
        dma_wr_ready_o = act_wr_ready;
      end
      // Accumulator: 0x0004_0000 - 0x0004_7FFF
      else if (dma_wr_addr_i[19:15] == 5'b00100) begin
        acc_wr_en = 1'b1;
        acc_wr_addr = dma_wr_addr_i[$clog2(ACC_DEPTH)-1:0];
        dma_wr_ready_o = acc_wr_ready;
      end
    end
  end
  
  // Instantiate Weight Buffer
  weight_buffer #(
      .DEPTH(WEIGHT_DEPTH),
      .DATA_WIDTH(DATA_WIDTH),
      .NUM_BANKS(4)
  ) i_weight_buffer (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .wr_en_i(weight_wr_en),
      .wr_addr_i(weight_wr_addr),
      .wr_data_i(dma_wr_data_i),
      .wr_ready_o(weight_wr_ready),
      .rd_en_i(weight_rd_en_i),
      .rd_addr_i(weight_rd_addr_i),
      .rd_data_o(weight_rd_data_o),
      .rd_valid_o(weight_rd_valid_o)
  );
  
  // Instantiate Activation Buffer (with ping-pong)
  activation_buffer #(
      .DEPTH(ACT_DEPTH),
      .DATA_WIDTH(DATA_WIDTH),
      .NUM_LANES(NUM_LANES),
      .LANE_WIDTH(LANE_WIDTH)
  ) i_activation_buffer (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .ping_pong_sel_i(ping_pong_sel_i),
      .wr_en_i(act_wr_en),
      .wr_addr_i(act_wr_addr),
      .wr_data_i(dma_wr_data_i),
      .wr_ready_o(act_wr_ready),
      .rd_en_i(1'b0),  // Not used (use wide_rd)
      .rd_addr_i('0),
      .rd_data_o(),
      .rd_valid_o(),
      .wide_rd_en_i(act_rd_en_i),
      .wide_rd_addr_i(act_rd_addr_i),
      .wide_rd_data_o(act_rd_data_o),
      .wide_rd_valid_o(act_rd_valid_o)
  );
  
  // Instantiate Accumulator Buffer
  accumulator_buffer #(
      .DEPTH(ACC_DEPTH),
      .DATA_WIDTH(DATA_WIDTH),
      .NUM_LANES(NUM_LANES),
      .LANE_WIDTH(LANE_WIDTH)
  ) i_accumulator_buffer (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .rmw_en_i(acc_rmw_en_i),
      .rmw_addr_i(acc_rmw_addr_i),
      .rmw_data_i(acc_rmw_data_i),
      .rmw_result_o(acc_rmw_result_o),
      .rmw_ready_o(acc_rmw_ready_o),
      .wr_en_i(1'b0),  // Not used (use RMW)
      .wr_addr_i('0),
      .wr_data_i('0),
      .wr_ready_o(),
      .rd_en_i(1'b0),  // Not used
      .rd_addr_i('0),
      .rd_data_o(),
      .rd_valid_o(),
      .wide_rd_en_i(1'b0),
      .wide_rd_addr_i('0),
      .wide_rd_data_o(),
      .wide_rd_valid_o()
  );

endmodule
