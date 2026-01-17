// Multi-Lane MAC Unit with DMA Integration
// Combines multi-lane unit with DMA engine for high-performance operation
// Phase 2.1 + 2.2 of Production Roadmap

module multilane_with_dma #(
    parameter int unsigned XLEN         = 32,
    parameter int unsigned NUM_LANES    = 16,
    parameter int unsigned LANE_WIDTH   = 32,
    parameter int unsigned DATA_WIDTH   = 32,
    parameter int unsigned ADDR_WIDTH   = 32,
    parameter int unsigned BUFFER_DEPTH = 4096,  // 16KB buffer
    parameter type         opcode_t     = logic,
    parameter type         hartid_t     = logic,
    parameter type         id_t         = logic
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,
    
    // CVXIF interface (standard)
    input  logic [XLEN-1:0]              rs1_i,
    input  logic [XLEN-1:0]              rs2_i,
    input  logic [XLEN-1:0]              rd_i,
    input  opcode_t                      opcode_i,
    input  hartid_t                      hartid_i,
    input  id_t                          id_i,
    input  logic [4:0]                   rd_addr_i,
    input  logic                         valid_i,
    
    // DMA configuration (memory-mapped registers)
    input  logic                         dma_cfg_valid_i,
    input  logic [ADDR_WIDTH-1:0]        dma_src_addr_i,
    input  logic [ADDR_WIDTH-1:0]        dma_dst_addr_i,
    input  logic [ADDR_WIDTH-1:0]        dma_size_i,
    input  logic                         dma_start_i,
    output logic                         dma_ready_o,
    output logic                         dma_done_o,
    
    // AXI interface (to system memory)
    output logic                         axi_arvalid_o,
    input  logic                         axi_arready_i,
    output logic [ADDR_WIDTH-1:0]        axi_araddr_o,
    output logic [7:0]                   axi_arlen_o,
    output logic [2:0]                   axi_arsize_o,
    
    input  logic                         axi_rvalid_i,
    output logic                         axi_rready_o,
    input  logic [DATA_WIDTH-1:0]        axi_rdata_i,
    input  logic                         axi_rlast_i,
    
    // CVXIF result output
    output logic [XLEN-1:0]              result_o,
    output logic                         valid_o,
    output logic                         we_o,
    output logic [4:0]                   rd_addr_o,
    output hartid_t                      hartid_o,
    output id_t                          id_o,
    output logic                         overflow_o
);

  // DMA engine instance
  logic                        dma_data_valid;
  logic                        dma_data_ready;
  logic [NUM_LANES*LANE_WIDTH-1:0] dma_data;
  
  dma_engine #(
      .DATA_WIDTH(DATA_WIDTH),
      .ADDR_WIDTH(ADDR_WIDTH),
      .NUM_LANES(NUM_LANES),
      .LANE_WIDTH(LANE_WIDTH)
  ) i_dma (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .cfg_valid_i(dma_cfg_valid_i),
      .cfg_src_addr_i(dma_src_addr_i),
      .cfg_dst_addr_i(dma_dst_addr_i),
      .cfg_size_i(dma_size_i),
      .cfg_start_i(dma_start_i),
      .cfg_ready_o(dma_ready_o),
      .cfg_done_o(dma_done_o),
      .cfg_error_o(),
      .axi_arvalid_o(axi_arvalid_o),
      .axi_arready_i(axi_arready_i),
      .axi_araddr_o(axi_araddr_o),
      .axi_arlen_o(axi_arlen_o),
      .axi_arsize_o(axi_arsize_o),
      .axi_arburst_o(),
      .axi_rvalid_i(axi_rvalid_i),
      .axi_rready_o(axi_rready_o),
      .axi_rdata_i(axi_rdata_i),
      .axi_rlast_i(axi_rlast_i),
      .data_valid_o(dma_data_valid),
      .data_ready_i(dma_data_ready),
      .data_o(dma_data),
      .busy_o()
  );
  
  // On-chip buffer for DMA data
  logic                        buffer_wr_en;
  logic [$clog2(BUFFER_DEPTH)-1:0] buffer_wr_addr;
  logic [NUM_LANES*LANE_WIDTH-1:0] buffer_wr_data;
  
  logic                        buffer_rd_en;
  logic [$clog2(BUFFER_DEPTH)-1:0] buffer_rd_addr;
  logic [NUM_LANES*LANE_WIDTH-1:0] buffer_rd_data;
  
  onchip_buffer #(
      .DEPTH(BUFFER_DEPTH),
      .DATA_WIDTH(NUM_LANES * LANE_WIDTH),
      .NUM_BANKS(2),
      .NUM_PORTS(2)
  ) i_buffer (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .wr_en_i(buffer_wr_en),
      .wr_addr_i(buffer_wr_addr),
      .wr_data_i(buffer_wr_data),
      .rd_en_i(buffer_rd_en),
      .rd_addr_i(buffer_rd_addr),
      .rd_data_o(buffer_rd_data),
      .bank_sel_i(1'b0)
  );
  
  // Buffer write from DMA
  assign buffer_wr_en = dma_data_valid;
  assign buffer_wr_addr = 0;  // Simplified: single buffer entry
  assign buffer_wr_data = dma_data;
  assign dma_data_ready = 1'b1;  // Buffer always ready (simplified)
  
  // Multi-lane unit instance
  logic                        ml_valid;
  logic [NUM_LANES*LANE_WIDTH-1:0] ml_rs1, ml_rs2;
  
  // Select data source: from DMA buffer or from CVXIF registers
  always_comb begin
    ml_rs1 = '0;
    ml_rs2 = '0;
    ml_valid = 1'b0;
    
    // For SIMD_DOT with DMA: use buffer data
    // For other operations: use CVXIF register data
    if (opcode_i == opcode_t'(5)) begin  // SIMD_DOT
      ml_rs1 = buffer_rd_data[NUM_LANES*LANE_WIDTH-1 : NUM_LANES*LANE_WIDTH/2];
      ml_rs2 = buffer_rd_data[NUM_LANES*LANE_WIDTH/2-1 : 0];
      ml_valid = valid_i && dma_done_o;  // Valid when DMA complete
    end else begin
      // Scalar operations use CVXIF data
      ml_rs1 = {rs1_i, {(NUM_LANES-1)*LANE_WIDTH{1'b0}}};
      ml_rs2 = {rs2_i, {(NUM_LANES-1)*LANE_WIDTH{1'b0}}};
      ml_valid = valid_i;
    end
  end
  
  assign buffer_rd_en = (opcode_i == opcode_t'(5)) && valid_i;
  assign buffer_rd_addr = 0;  // Single buffer entry (simplified)
  
  // Multi-lane wrapper
  int8_mac_multilane_wrapper #(
      .XLEN(XLEN),
      .NUM_LANES(NUM_LANES),
      .LANE_WIDTH(LANE_WIDTH),
      .opcode_t(opcode_t),
      .hartid_t(hartid_t),
      .id_t(id_t)
  ) i_multilane (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .rs1_i(ml_rs1[XLEN-1:0]),  // Only lower 32 bits used for scalar ops
      .rs2_i(ml_rs2[XLEN-1:0]),
      .rd_i(rd_i),
      .opcode_i(opcode_i),
      .hartid_i(hartid_i),
      .id_i(id_i),
      .rd_addr_i(rd_addr_i),
      .valid_i(ml_valid),
      .lane_idx_i('0),  // Not used when DMA provides wide data
      .lane_load_i(1'b0),
      .lane_exec_i(ml_valid),
      .result_o(result_o),
      .valid_o(valid_o),
      .we_o(we_o),
      .rd_addr_o(rd_addr_o),
      .hartid_o(hartid_o),
      .id_o(id_o),
      .overflow_o(overflow_o)
  );

endmodule
