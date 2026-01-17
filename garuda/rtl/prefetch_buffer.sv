// Prefetch Buffer - Predicts and loads data ahead of use
// Phase 2.3 of Production Roadmap: Memory Coalescing
// Prefetches data from memory to reduce latency

module prefetch_buffer #(
    parameter int unsigned DEPTH          = 16,   // Prefetch buffer depth (entries)
    parameter int unsigned DATA_WIDTH     = 32,  // Data width (bytes per entry)
    parameter int unsigned ADDR_WIDTH     = 32,   // Address width
    parameter int unsigned PREFETCH_DISTANCE = 64  // Prefetch distance (bytes ahead)
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,
    
    // Access prediction (from execution unit or pattern predictor)
    input  logic                        predict_valid_i,
    input  logic [ADDR_WIDTH-1:0]       predict_addr_i,  // Address to prefetch
    input  logic [ADDR_WIDTH-1:0]       predict_size_i,  // Size to prefetch
    output logic                        predict_ready_o,
    
    // Prefetch request to DMA/memory
    output logic                        prefetch_req_valid_o,
    output logic [ADDR_WIDTH-1:0]       prefetch_addr_o,
    output logic [ADDR_WIDTH-1:0]       prefetch_size_o,
    input  logic                        prefetch_req_ready_i,
    
    // Data input (from DMA/memory)
    input  logic                        data_valid_i,
    input  logic [DATA_WIDTH-1:0]       data_addr_i,
    input  logic [DEPTH*DATA_WIDTH-1:0] data_i,  // Wide data from DMA
    output logic                        data_ready_o,
    
    // Data output (to execution unit)
    output logic                        output_valid_o,
    output logic [ADDR_WIDTH-1:0]       output_addr_o,
    output logic [DEPTH*DATA_WIDTH-1:0] output_data_o,
    input  logic                        output_ready_i,
    
    // Status
    output logic                        full_o,
    output logic                        empty_o
);

  // Prefetch buffer entry
  typedef struct packed {
    logic [ADDR_WIDTH-1:0] addr;
    logic [DEPTH*DATA_WIDTH-1:0] data;
    logic                     valid;
  } prefetch_entry_t;
  
  // Prefetch buffer (circular FIFO)
  prefetch_entry_t buffer [DEPTH];
  logic [$clog2(DEPTH)-1:0] wr_ptr_q, wr_ptr_d;
  logic [$clog2(DEPTH)-1:0] rd_ptr_q, rd_ptr_d;
  logic [$clog2(DEPTH):0]   count_q, count_d;
  
  // Prefetch address calculation (ahead of current access)
  logic [ADDR_WIDTH-1:0] prefetch_addr;
  assign prefetch_addr = predict_addr_i + PREFETCH_DISTANCE;
  
  // Prefetch request generation
  always_comb begin
    predict_ready_o = (count_q < DEPTH);
    prefetch_req_valid_o = predict_valid_i && (count_q < DEPTH) && prefetch_req_ready_i;
    prefetch_addr_o = prefetch_addr;
    prefetch_size_o = predict_size_i;
  end
  
  // Buffer write (from DMA)
  always_comb begin
    data_ready_o = (count_q < DEPTH);
    wr_ptr_d = wr_ptr_q;
    count_d = count_q;
    
    if (data_valid_i && (count_q < DEPTH)) begin
      wr_ptr_d = (wr_ptr_q + 1) % DEPTH;
      count_d = count_q + 1;
    end
  end
  
  // Buffer read (to execution unit)
  always_comb begin
    output_valid_o = (count_q > 0) && buffer[rd_ptr_q].valid;
    output_addr_o = buffer[rd_ptr_q].addr;
    output_data_o = buffer[rd_ptr_q].data;
    rd_ptr_d = rd_ptr_q;
    count_d = count_q;
    
    if (output_valid_o && output_ready_i) begin
      rd_ptr_d = (rd_ptr_q + 1) % DEPTH;
      count_d = count_q - 1;
    end
  end
  
  assign full_o = (count_q == DEPTH);
  assign empty_o = (count_q == 0);
  
  // Sequential logic
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int i = 0; i < DEPTH; i++) begin
        buffer[i] <= '0;
      end
      wr_ptr_q <= '0;
      rd_ptr_q <= '0;
      count_q <= '0;
    end else begin
      // Write prefetched data
      if (data_valid_i && (count_q < DEPTH)) begin
        buffer[wr_ptr_q].addr <= data_addr_i;
        buffer[wr_ptr_q].data <= data_i;
        buffer[wr_ptr_q].valid <= 1'b1;
      end
      
      // Invalidate read data
      if (output_valid_o && output_ready_i) begin
        buffer[rd_ptr_q].valid <= 1'b0;
      end
      
      wr_ptr_q <= wr_ptr_d;
      rd_ptr_q <= rd_ptr_d;
      count_q <= count_d;
    end
  end

endmodule
