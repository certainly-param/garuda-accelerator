// Memory Coalescing Unit - Merges memory requests for optimal burst transfers
// Phase 2.3 of Production Roadmap: Memory Coalescing
// Coalesces multiple memory requests into optimized burst transfers

module memory_coalescing_unit #(
    parameter int unsigned ADDR_WIDTH      = 32,
    parameter int unsigned DATA_WIDTH      = 32,
    parameter int unsigned REQ_QUEUE_DEPTH = 8,   // Request queue depth
    parameter int unsigned MAX_BURST_SIZE  = 128, // Maximum burst size (bytes)
    parameter int unsigned COALESCE_WINDOW = 64   // Coalescing window (bytes)
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,
    
    // Memory request input (from execution units)
    input  logic                        req_valid_i,
    input  logic [ADDR_WIDTH-1:0]       req_addr_i,
    input  logic [ADDR_WIDTH-1:0]       req_size_i,  // Request size (bytes)
    input  logic                        req_read_i,   // 1=read, 0=write
    output logic                        req_ready_o,
    
    // Coalesced memory request output (to DMA/AXI)
    output logic                        coalesced_valid_o,
    output logic [ADDR_WIDTH-1:0]       coalesced_addr_o,
    output logic [ADDR_WIDTH-1:0]       coalesced_size_o,
    output logic [7:0]                  coalesced_burst_len_o,
    output logic [2:0]                  coalesced_burst_size_o,
    output logic                        coalesced_read_o,
    input  logic                        coalesced_ready_i,
    
    // Status
    output logic                        busy_o,
    output logic [$clog2(REQ_QUEUE_DEPTH):0] queue_count_o
);

  // Memory request entry structure
  typedef struct packed {
    logic [ADDR_WIDTH-1:0] addr;
    logic [ADDR_WIDTH-1:0] size;
    logic                  read;
    logic                  valid;
  } mem_req_t;
  
  // Request queue (FIFO)
  mem_req_t req_queue [REQ_QUEUE_DEPTH];
  logic [$clog2(REQ_QUEUE_DEPTH)-1:0] wr_ptr_q, wr_ptr_d;
  logic [$clog2(REQ_QUEUE_DEPTH)-1:0] rd_ptr_q, rd_ptr_d;
  logic [$clog2(REQ_QUEUE_DEPTH):0]   count_q, count_d;
  
  // Coalescing state
  typedef enum logic [1:0] {
    IDLE,
    COALESCE,
    BURST_OUTPUT
  } coalesce_state_t;

  coalesce_state_t state_q, state_d;
  
  logic [ADDR_WIDTH-1:0] coalesce_start_addr_q, coalesce_start_addr_d;
  logic [ADDR_WIDTH-1:0] coalesce_end_addr_q, coalesce_end_addr_d;
  logic [ADDR_WIDTH-1:0] coalesce_size_q, coalesce_size_d;
  logic                  coalesce_read_q, coalesce_read_d;
  logic [2:0]            coalesce_read_count_q, coalesce_read_count_d;
  
  // Request queue management
  always_comb begin
    wr_ptr_d = wr_ptr_q;
    count_d = count_q;
    req_ready_o = (count_q < REQ_QUEUE_DEPTH);
    
    if (req_valid_i && (count_q < REQ_QUEUE_DEPTH)) begin
      wr_ptr_d = (wr_ptr_q + 1) % REQ_QUEUE_DEPTH;
      count_d = count_q + 1;
    end
  end
  
  // Coalescing logic
  always_comb begin
    state_d = state_q;
    rd_ptr_d = rd_ptr_q;
    count_d = count_q;
    coalesce_start_addr_d = coalesce_start_addr_q;
    coalesce_end_addr_d = coalesce_end_addr_q;
    coalesce_size_d = coalesce_size_q;
    coalesce_read_d = coalesce_read_q;
    coalesce_read_count_d = coalesce_read_count_q;
    
    coalesced_valid_o = 1'b0;
    coalesced_addr_o = coalesce_start_addr_q;
    coalesced_size_o = coalesce_size_q;
    coalesced_burst_len_o = '0;
    coalesced_burst_size_o = 3'b010;  // 4 bytes default
    coalesced_read_o = coalesce_read_q;
    busy_o = (state_q != IDLE);
    queue_count_o = count_q;
    
    case (state_q)
      IDLE: begin
        if (count_q > 0) begin
          mem_req_t first_req;
          first_req = req_queue[rd_ptr_q];
          
          if (first_req.valid) begin
            coalesce_start_addr_d = first_req.addr;
            coalesce_end_addr_d = first_req.addr + first_req.size;
            coalesce_size_d = first_req.size;
            coalesce_read_d = first_req.read;
            coalesce_read_count_d = 1;
            state_d = COALESCE;
          end
        end
      end
      
      COALESCE: begin
        // Try to coalesce with next request in queue
        if (count_q > coalesce_read_count_q) begin
          mem_req_t next_req;
          logic [$clog2(REQ_QUEUE_DEPTH)-1:0] next_ptr;
          next_ptr = (rd_ptr_q + coalesce_read_count_q) % REQ_QUEUE_DEPTH;
          next_req = req_queue[next_ptr];
          
          // Check if we can coalesce:
          // 1. Same type (read/write)
          // 2. Adjacent or within coalescing window
          // 3. Total size within max burst size
          logic [ADDR_WIDTH-1:0] distance;
          logic [ADDR_WIDTH-1:0] new_size;
          logic                  can_coalesce;
          
          distance = (next_req.addr > coalesce_end_addr_q) ? 
                     (next_req.addr - coalesce_end_addr_q) : 
                     (coalesce_end_addr_q - next_req.addr);
          new_size = coalesce_end_addr_q - coalesce_start_addr_q + next_req.size;
          can_coalesce = (next_req.valid) && 
                         (next_req.read == coalesce_read_q) &&
                         (distance < COALESCE_WINDOW) &&
                         (new_size <= MAX_BURST_SIZE);
          
          if (can_coalesce) begin
            // Coalesce with next request
            if (next_req.addr > coalesce_end_addr_q) begin
              coalesce_end_addr_d = next_req.addr + next_req.size;
            end else begin
              coalesce_start_addr_d = next_req.addr;
            end
            coalesce_size_d = coalesce_end_addr_d - coalesce_start_addr_d;
            coalesce_read_count_d = coalesce_read_count_q + 1;
          end else begin
            // Cannot coalesce further, output burst
            state_d = BURST_OUTPUT;
          end
        end else begin
          // No more requests, output burst
          state_d = BURST_OUTPUT;
        end
      end
      
      BURST_OUTPUT: begin
        coalesced_valid_o = 1'b1;
        
        // Calculate burst parameters
        coalesced_burst_size_o = 3'b010;  // 4 bytes (32-bit)
        coalesced_burst_len_o = ((coalesce_size_q >> 2) > 256) ? 
                                255 : ((coalesce_size_q >> 2) - 1);
        
        if (coalesced_ready_i) begin
          // Remove coalesced requests from queue
          rd_ptr_d = (rd_ptr_q + coalesce_read_count_q) % REQ_QUEUE_DEPTH;
          count_d = count_q - coalesce_read_count_q;
          
          if (count_d == 0) begin
            state_d = IDLE;
          end else begin
            state_d = COALESCE;
          end
        end
      end
      
      default: begin
        state_d = IDLE;
      end
    endcase
  end
  
  // Sequential logic for request queue
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int i = 0; i < REQ_QUEUE_DEPTH; i++) begin
        req_queue[i] <= '0;
      end
      wr_ptr_q <= '0;
      rd_ptr_q <= '0;
      count_q <= '0;
      state_q <= IDLE;
      coalesce_start_addr_q <= '0;
      coalesce_end_addr_q <= '0;
      coalesce_size_q <= '0;
      coalesce_read_q <= 1'b0;
      coalesce_read_count_q <= '0;
    end else begin
      // Write new request
      if (req_valid_i && (count_q < REQ_QUEUE_DEPTH)) begin
        req_queue[wr_ptr_q].addr <= req_addr_i;
        req_queue[wr_ptr_q].size <= req_size_i;
        req_queue[wr_ptr_q].read <= req_read_i;
        req_queue[wr_ptr_q].valid <= 1'b1;
      end
      
      // Invalidate processed requests
      if ((state_q == BURST_OUTPUT) && coalesced_ready_i) begin
        for (int i = 0; i < coalesce_read_count_q; i++) begin
          req_queue[(rd_ptr_q + i) % REQ_QUEUE_DEPTH].valid <= 1'b0;
        end
      end
      
      wr_ptr_q <= wr_ptr_d;
      rd_ptr_q <= rd_ptr_d;
      count_q <= count_d;
      state_q <= state_d;
      coalesce_start_addr_q <= coalesce_start_addr_d;
      coalesce_end_addr_q <= coalesce_end_addr_d;
      coalesce_size_q <= coalesce_size_d;
      coalesce_read_q <= coalesce_read_d;
      coalesce_read_count_q <= coalesce_read_count_d;
    end
  end

endmodule
