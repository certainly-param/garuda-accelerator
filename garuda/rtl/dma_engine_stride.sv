// DMA Engine with Stride Support for Garuda Accelerator
// Extended version with stride support for matrix operations
// Phase 2.1 Enhancement: Stride Support

module dma_engine_stride #(
    parameter int unsigned DATA_WIDTH      = 32,  // AXI data width (32, 64, 128 bits)
    parameter int unsigned ADDR_WIDTH      = 32,  // Address width
    parameter int unsigned NUM_LANES       = 16,  // Number of lanes (matches multi-lane unit)
    parameter int unsigned LANE_WIDTH      = 32,  // Width per lane
    parameter int unsigned MAX_BURST_LEN   = 16   // Maximum burst length
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,
    
    // Configuration/Control Interface (AXI4-Lite style)
    input  logic                        cfg_valid_i,
    input  logic [ADDR_WIDTH-1:0]       cfg_src_addr_i,    // Source address
    input  logic [ADDR_WIDTH-1:0]       cfg_dst_addr_i,    // Destination address
    input  logic [ADDR_WIDTH-1:0]       cfg_size_i,        // Transfer size (bytes or row size for 2D)
    input  logic [ADDR_WIDTH-1:0]       cfg_src_stride_i,  // Source stride (bytes between rows)
    input  logic [ADDR_WIDTH-1:0]       cfg_dst_stride_i,  // Destination stride (bytes between rows)
    input  logic [15:0]                 cfg_rows_i,        // Number of rows (for 2D transfer)
    input  logic                        cfg_2d_mode_i,     // 1 = 2D mode, 0 = 1D mode
    input  logic                        cfg_start_i,       // Start DMA transfer
    output logic                        cfg_ready_o,
    output logic                        cfg_done_o,        // Transfer complete
    output logic                        cfg_error_o,       // Transfer error
    
    // AXI4 Read Interface (for reading from memory)
    output logic                        axi_arvalid_o,
    input  logic                        axi_arready_i,
    output logic [ADDR_WIDTH-1:0]       axi_araddr_o,
    output logic [7:0]                  axi_arlen_o,       // Burst length -1
    output logic [2:0]                  axi_arsize_o,      // Burst size
    output logic [1:0]                  axi_arburst_o,     // Burst type (INCR)
    
    input  logic                        axi_rvalid_i,
    output logic                        axi_rready_o,
    input  logic [DATA_WIDTH-1:0]       axi_rdata_i,
    input  logic                        axi_rlast_i,
    
    // Data output to accelerator buffers
    output logic                        data_valid_o,
    output logic [NUM_LANES*LANE_WIDTH-1:0] data_o,  // Wide data bus
    input  logic                        data_ready_i,
    
    // Status
    output logic                        busy_o             // DMA is active
);

  // DMA State Machine
  typedef enum logic [2:0] {
    IDLE,
    READ_ADDR,
    READ_DATA,
    STRIDE_PAUSE,  // Pause between rows (2D mode)
    DONE,
    ERROR
  } dma_state_t;

  dma_state_t state_q, state_d;
  
  // Address and size registers
  logic [ADDR_WIDTH-1:0] src_addr_q, src_addr_d;
  logic [ADDR_WIDTH-1:0] dst_addr_q, dst_addr_d;
  logic [ADDR_WIDTH-1:0] size_q, size_d;
  logic [ADDR_WIDTH-1:0] bytes_remaining_q, bytes_remaining_d;
  logic [ADDR_WIDTH-1:0] src_stride_q, src_stride_d;
  logic [ADDR_WIDTH-1:0] dst_stride_q, dst_stride_d;
  logic [15:0]           rows_q, rows_d;
  logic [15:0]           rows_remaining_q, rows_remaining_d;
  logic                  mode_2d_q, mode_2d_d;
  
  // Data accumulation buffer (for wide output)
  logic [NUM_LANES*LANE_WIDTH-1:0] data_buffer_q, data_buffer_d;
  logic [$clog2(NUM_LANES*LANE_WIDTH/DATA_WIDTH)-1:0] word_count_q, word_count_d;
  
  // Control signals
  logic start_transfer;
  logic burst_complete;
  logic transfer_complete;
  logic row_complete;
  logic buffer_full;
  
  // AXI signals
  logic [7:0] burst_len;
  logic [2:0] burst_size;
  
  // Compute burst length and size
  always_comb begin
    // Calculate how many words needed for one lane
    int words_per_lane = LANE_WIDTH / DATA_WIDTH;
    int total_words = NUM_LANES * words_per_lane;
    
    // For 2D mode, use row size; for 1D mode, use remaining bytes
    logic [ADDR_WIDTH-1:0] current_size;
    if (mode_2d_q) begin
      current_size = size_q;  // Row size
    end else begin
      current_size = bytes_remaining_q;  // Remaining bytes
    end
    
    // Use smaller burst to avoid buffer overflow
    if (current_size >= (total_words * DATA_WIDTH / 8)) begin
      burst_len = (total_words < MAX_BURST_LEN) ? (total_words - 1) : (MAX_BURST_LEN - 1);
    end else begin
      burst_len = ((current_size / (DATA_WIDTH / 8)) - 1);
    end
    
    // Burst size based on DATA_WIDTH
    case (DATA_WIDTH)
      32:  burst_size = 3'b010;  // 4 bytes
      64:  burst_size = 3'b011;  // 8 bytes
      128: burst_size = 3'b100;  // 16 bytes
      default: burst_size = 3'b010;
    endcase
  end
  
  // State machine
  always_comb begin
    state_d = state_q;
    src_addr_d = src_addr_q;
    dst_addr_d = dst_addr_q;
    size_d = size_q;
    bytes_remaining_d = bytes_remaining_q;
    src_stride_d = src_stride_q;
    dst_stride_d = dst_stride_q;
    rows_d = rows_q;
    rows_remaining_d = rows_remaining_q;
    mode_2d_d = mode_2d_q;
    data_buffer_d = data_buffer_q;
    word_count_d = word_count_q;
    
    cfg_ready_o = 1'b0;
    cfg_done_o = 1'b0;
    cfg_error_o = 1'b0;
    
    axi_arvalid_o = 1'b0;
    axi_araddr_o = src_addr_q;
    axi_arlen_o = burst_len;
    axi_arsize_o = burst_size;
    axi_arburst_o = 2'b01;  // INCR burst
    
    axi_rready_o = 1'b0;
    
    data_valid_o = 1'b0;
    data_o = data_buffer_q;
    
    busy_o = (state_q != IDLE);
    
    start_transfer = cfg_valid_i && cfg_start_i;
    buffer_full = (word_count_q == (NUM_LANES * LANE_WIDTH / DATA_WIDTH));
    
    // For 2D mode: check row completion; for 1D mode: check total completion
    if (mode_2d_q) begin
      row_complete = (bytes_remaining_q == 0);
      transfer_complete = (rows_remaining_q == 0);
    end else begin
      row_complete = 1'b0;
      transfer_complete = (bytes_remaining_q == 0);
    end
    
    case (state_q)
      IDLE: begin
        cfg_ready_o = 1'b1;
        if (start_transfer) begin
          src_addr_d = cfg_src_addr_i;
          dst_addr_d = cfg_dst_addr_i;
          size_d = cfg_size_i;
          bytes_remaining_d = (cfg_2d_mode_i) ? cfg_size_i : cfg_size_i;
          src_stride_d = cfg_src_stride_i;
          dst_stride_d = cfg_dst_stride_i;
          rows_d = cfg_rows_i;
          rows_remaining_d = (cfg_2d_mode_i) ? cfg_rows_i : 16'd1;
          mode_2d_d = cfg_2d_mode_i;
          word_count_d = '0;
          data_buffer_d = '0;
          state_d = READ_ADDR;
        end
      end
      
      READ_ADDR: begin
        axi_arvalid_o = 1'b1;
        if (axi_arready_i) begin
          state_d = READ_DATA;
        end
      end
      
      READ_DATA: begin
        axi_rready_o = 1'b1;
        
        if (axi_rvalid_i) begin
          // Accumulate data into buffer
          int word_idx = word_count_q;
          int bit_offset = word_idx * DATA_WIDTH;
          
          if (bit_offset < (NUM_LANES * LANE_WIDTH)) begin
            data_buffer_d[bit_offset +: DATA_WIDTH] = axi_rdata_i;
            word_count_d = word_count_d + 1;
            bytes_remaining_d = bytes_remaining_d - (DATA_WIDTH / 8);
          end
          
          // If buffer is full or burst complete, output data
          if (buffer_full || axi_rlast_i) begin
            if (data_ready_i) begin
              data_valid_o = 1'b1;
              word_count_d = '0;
              data_buffer_d = '0;
            end
          end
          
          // Handle completion based on mode
          if (mode_2d_q) begin
            // 2D mode: check row completion
            if (row_complete && axi_rlast_i) begin
              rows_remaining_d = rows_remaining_q - 1;
              if (transfer_complete) begin
                state_d = DONE;
              end else begin
                // Move to next row: apply stride
                src_addr_d = src_addr_q + src_stride_q;
                dst_addr_d = dst_addr_q + dst_stride_q;
                bytes_remaining_d = size_q;  // Reset for next row
                state_d = STRIDE_PAUSE;
              end
            end else if (axi_rlast_i && !row_complete) begin
              // Next burst within same row
              src_addr_d = src_addr_q + ((burst_len + 1) * (DATA_WIDTH / 8));
              state_d = READ_ADDR;
            end
          end else begin
            // 1D mode: standard transfer
            if (transfer_complete && axi_rlast_i) begin
              if (data_ready_i || !buffer_full) begin
                state_d = DONE;
              end
            end else if (axi_rlast_i && !transfer_complete) begin
              // Next burst
              src_addr_d = src_addr_q + ((burst_len + 1) * (DATA_WIDTH / 8));
              state_d = READ_ADDR;
            end
          end
        end
      end
      
      STRIDE_PAUSE: begin
        // One cycle pause between rows (for address generation)
        state_d = READ_ADDR;
      end
      
      DONE: begin
        cfg_done_o = 1'b1;
        if (!cfg_valid_i) begin
          state_d = IDLE;
        end
      end
      
      ERROR: begin
        cfg_error_o = 1'b1;
        if (!cfg_valid_i) begin
          state_d = IDLE;
        end
      end
      
      default: begin
        state_d = IDLE;
      end
    endcase
  end
  
  // Sequential logic
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE;
      src_addr_q <= '0;
      dst_addr_q <= '0;
      size_q <= '0;
      bytes_remaining_q <= '0;
      src_stride_q <= '0;
      dst_stride_q <= '0;
      rows_q <= '0;
      rows_remaining_q <= '0;
      mode_2d_q <= 1'b0;
      data_buffer_q <= '0;
      word_count_q <= '0;
    end else begin
      state_q <= state_d;
      src_addr_q <= src_addr_d;
      dst_addr_q <= dst_addr_d;
      size_q <= size_d;
      bytes_remaining_q <= bytes_remaining_d;
      src_stride_q <= src_stride_d;
      dst_stride_q <= dst_stride_d;
      rows_q <= rows_d;
      rows_remaining_q <= rows_remaining_d;
      mode_2d_q <= mode_2d_d;
      data_buffer_q <= data_buffer_d;
      word_count_q <= word_count_d;
    end
  end

endmodule
