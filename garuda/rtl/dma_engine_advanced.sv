// DMA Engine with Advanced Features for Garuda Accelerator
// Includes: Interrupts, Command Queue, and Scatter-Gather support
// Phase 2.1 Enhancement: Advanced DMA Features

module dma_engine_advanced #(
    parameter int unsigned DATA_WIDTH      = 32,  // AXI data width (32, 64, 128 bits)
    parameter int unsigned ADDR_WIDTH      = 32,  // Address width
    parameter int unsigned NUM_LANES       = 16,  // Number of lanes (matches multi-lane unit)
    parameter int unsigned LANE_WIDTH      = 32,  // Width per lane
    parameter int unsigned MAX_BURST_LEN   = 16,  // Maximum burst length
    parameter int unsigned CMD_QUEUE_DEPTH = 8,   // Command queue depth
    parameter int unsigned DESC_MAX        = 16   // Maximum scatter-gather descriptors
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,
    
    // Configuration/Control Interface (AXI4-Lite style)
    input  logic                        cfg_valid_i,
    input  logic [ADDR_WIDTH-1:0]       cfg_src_addr_i,    // Source address
    input  logic [ADDR_WIDTH-1:0]       cfg_dst_addr_i,    // Destination address
    input  logic [ADDR_WIDTH-1:0]       cfg_size_i,        // Transfer size in bytes
    input  logic                        cfg_start_i,       // Start DMA transfer
    input  logic                        cfg_queue_en_i,    // Enable command queue mode
    input  logic                        cfg_sg_en_i,       // Enable scatter-gather mode
    input  logic [ADDR_WIDTH-1:0]       cfg_desc_addr_i, // Scatter-gather descriptor list address
    output logic                        cfg_ready_o,
    output logic                        cfg_done_o,        // Transfer complete
    output logic                        cfg_error_o,       // Transfer error
    output logic [ADDR_WIDTH-1:0]       cfg_bytes_transferred_o, // Bytes transferred
    
    // Command Queue Interface
    input  logic                        cmd_enqueue_i,     // Enqueue command
    input  logic [ADDR_WIDTH-1:0]       cmd_src_addr_i,
    input  logic [ADDR_WIDTH-1:0]       cmd_dst_addr_i,
    input  logic [ADDR_WIDTH-1:0]       cmd_size_i,
    output logic                        cmd_full_o,        // Queue full
    output logic                        cmd_empty_o,       // Queue empty
    output logic [$clog2(CMD_QUEUE_DEPTH)-1:0] cmd_count_o, // Queue count
    
    // Interrupt Interface
    output logic                        irq_o,              // Interrupt request
    output logic                        irq_done_o,        // Completion interrupt
    output logic                        irq_error_o,       // Error interrupt
    input  logic                        irq_enable_i,      // Enable interrupts
    input  logic                        irq_clear_i,       // Clear interrupt status
    
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

  // ============================================================================
  // Scatter-Gather Descriptor Structure
  // ============================================================================
  typedef struct packed {
    logic [ADDR_WIDTH-1:0] src_addr;
    logic [ADDR_WIDTH-1:0] dst_addr;
    logic [ADDR_WIDTH-1:0] size;
    logic                  last;  // Last descriptor in chain
  } dma_descriptor_t;
  
  // Descriptor storage (for reading from memory)
  dma_descriptor_t current_desc_q, current_desc_d;
  
  // ============================================================================
  // Command Queue Structure
  // ============================================================================
  typedef struct packed {
    logic [ADDR_WIDTH-1:0] src_addr;
    logic [ADDR_WIDTH-1:0] dst_addr;
    logic [ADDR_WIDTH-1:0] size;
    logic                  valid;
  } dma_cmd_t;
  
  // Command queue FIFO
  dma_cmd_t cmd_queue [CMD_QUEUE_DEPTH];
  logic [$clog2(CMD_QUEUE_DEPTH)-1:0] cmd_wr_ptr_q, cmd_wr_ptr_d;
  logic [$clog2(CMD_QUEUE_DEPTH)-1:0] cmd_rd_ptr_q, cmd_rd_ptr_d;
  logic [$clog2(CMD_QUEUE_DEPTH):0] cmd_count_q, cmd_count_d;
  
  // ============================================================================
  // DMA State Machine
  // ============================================================================
  typedef enum logic [3:0] {
    IDLE,
    LOAD_DESC,        // Load scatter-gather descriptor
    READ_ADDR,
    READ_DATA,
    NEXT_DESC,        // Load next descriptor (scatter-gather)
    DONE,
    ERROR
  } dma_state_t;

  dma_state_t state_q, state_d;
  
  // Address and size registers
  logic [ADDR_WIDTH-1:0] src_addr_q, src_addr_d;
  logic [ADDR_WIDTH-1:0] dst_addr_q, dst_addr_d;
  logic [ADDR_WIDTH-1:0] size_q, size_d;
  logic [ADDR_WIDTH-1:0] bytes_remaining_q, bytes_remaining_d;
  logic [ADDR_WIDTH-1:0] bytes_transferred_q, bytes_transferred_d;
  
  // Mode control
  logic queue_mode_q, queue_mode_d;
  logic sg_mode_q, sg_mode_d;
  logic desc_addr_q, desc_addr_d;
  
  // Data accumulation buffer (for wide output)
  logic [NUM_LANES*LANE_WIDTH-1:0] data_buffer_q, data_buffer_d;
  logic [$clog2(NUM_LANES*LANE_WIDTH/DATA_WIDTH)-1:0] word_count_q, word_count_d;
  
  // Control signals
  logic start_transfer;
  logic transfer_complete;
  logic buffer_full;
  logic desc_last;
  
  // AXI signals
  logic [7:0] burst_len;
  logic [2:0] burst_size;
  
  // Interrupt registers
  logic irq_done_q, irq_done_d;
  logic irq_error_q, irq_error_d;
  
  // ============================================================================
  // Command Queue Management
  // ============================================================================
  assign cmd_full_o = (cmd_count_q == CMD_QUEUE_DEPTH);
  assign cmd_empty_o = (cmd_count_q == 0);
  assign cmd_count_o = cmd_count_q[$clog2(CMD_QUEUE_DEPTH)-1:0];
  
  // Command queue control signals
  logic cmd_enqueue;
  logic cmd_dequeue;
  dma_cmd_t current_cmd;
  
  assign cmd_enqueue = cmd_enqueue_i && !cmd_full_o;
  assign cmd_dequeue = (state_q == IDLE) && queue_mode_q && !cmd_empty_o && cmd_queue[cmd_rd_ptr_q].valid;
  assign current_cmd = cmd_queue[cmd_rd_ptr_q];
  
  // Enqueue/dequeue pointer updates
  always_comb begin
    cmd_wr_ptr_d = cmd_wr_ptr_q;
    cmd_rd_ptr_d = cmd_rd_ptr_q;
    cmd_count_d = cmd_count_q;
    
    if (cmd_enqueue) begin
      cmd_wr_ptr_d = (cmd_wr_ptr_q + 1) % CMD_QUEUE_DEPTH;
      cmd_count_d = cmd_count_q + 1;
    end
    
    if (cmd_dequeue) begin
      cmd_rd_ptr_d = (cmd_rd_ptr_q + 1) % CMD_QUEUE_DEPTH;
      cmd_count_d = cmd_count_q - 1;
    end
  end
  
  // ============================================================================
  // Interrupt Logic
  // ============================================================================
  always_comb begin
    irq_done_d = irq_done_q;
    irq_error_d = irq_error_q;
    
    // Set interrupt on completion
    if (state_q == DONE && !irq_done_q) begin
      irq_done_d = 1'b1;
    end
    
    // Set interrupt on error
    if (state_q == ERROR && !irq_error_q) begin
      irq_error_d = 1'b1;
    end
    
    // Clear interrupt
    if (irq_clear_i) begin
      irq_done_d = 1'b0;
      irq_error_d = 1'b0;
    end
  end
  
  assign irq_done_o = irq_done_q && irq_enable_i;
  assign irq_error_o = irq_error_q && irq_enable_i;
  assign irq_o = (irq_done_o || irq_error_o);
  
  // ============================================================================
  // Burst Length Calculation
  // ============================================================================
  always_comb begin
    int words_per_lane = LANE_WIDTH / DATA_WIDTH;
    int total_words = NUM_LANES * words_per_lane;
    
    if (bytes_remaining_q >= (total_words * DATA_WIDTH / 8)) begin
      burst_len = (total_words < MAX_BURST_LEN) ? (total_words - 1) : (MAX_BURST_LEN - 1);
    end else begin
      burst_len = ((bytes_remaining_q / (DATA_WIDTH / 8)) - 1);
    end
    
    case (DATA_WIDTH)
      32:  burst_size = 3'b010;  // 4 bytes
      64:  burst_size = 3'b011;  // 8 bytes
      128: burst_size = 3'b100;  // 16 bytes
      default: burst_size = 3'b010;
    endcase
  end
  
  // ============================================================================
  // State Machine
  // ============================================================================
  always_comb begin
    state_d = state_q;
    src_addr_d = src_addr_q;
    dst_addr_d = dst_addr_q;
    size_d = size_q;
    bytes_remaining_d = bytes_remaining_q;
    bytes_transferred_d = bytes_transferred_q;
    queue_mode_d = queue_mode_q;
    sg_mode_d = sg_mode_q;
    desc_addr_d = desc_addr_q;
    current_desc_d = current_desc_q;
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
    transfer_complete = (bytes_remaining_q == 0);
    desc_last = sg_mode_q ? current_desc_q.last : 1'b1;
    
    case (state_q)
      IDLE: begin
        cfg_ready_o = 1'b1;
        
        // Check for command queue
        if (cmd_dequeue) begin
          src_addr_d = current_cmd.src_addr;
          dst_addr_d = current_cmd.dst_addr;
          size_d = current_cmd.size;
          bytes_remaining_d = current_cmd.size;
          bytes_transferred_d = '0;
          word_count_d = '0;
          data_buffer_d = '0;
          queue_mode_d = 1'b1;
          sg_mode_d = 1'b0;
          state_d = READ_ADDR;
        end
        // Check for scatter-gather descriptor load
        else if (sg_mode_q && !transfer_complete) begin
          state_d = LOAD_DESC;
        end
        // Standard transfer start
        else if (start_transfer) begin
          src_addr_d = cfg_src_addr_i;
          dst_addr_d = cfg_dst_addr_i;
          size_d = cfg_size_i;
          bytes_remaining_d = cfg_size_i;
          bytes_transferred_d = '0;
          word_count_d = '0;
          data_buffer_d = '0;
          queue_mode_d = cfg_queue_en_i;
          sg_mode_d = cfg_sg_en_i;
          desc_addr_d = cfg_desc_addr_i[0];  // Simplified: use bit 0 as flag
          state_d = sg_mode_q ? LOAD_DESC : READ_ADDR;
        end
      end
      
      LOAD_DESC: begin
        // Simplified: In real implementation, read descriptor from memory via AXI
        // For now, use direct configuration as descriptor
        if (sg_mode_q) begin
          current_desc_d.src_addr = cfg_src_addr_i;
          current_desc_d.dst_addr = cfg_dst_addr_i;
          current_desc_d.size = cfg_size_i;
          current_desc_d.last = 1'b1;  // Simplified: assume single descriptor for now
          src_addr_d = cfg_src_addr_i;
          dst_addr_d = cfg_dst_addr_i;
          size_d = cfg_size_i;
          bytes_remaining_d = cfg_size_i;
        end
        state_d = READ_ADDR;
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
          int word_idx = word_count_q;
          int bit_offset = word_idx * DATA_WIDTH;
          
          if (bit_offset < (NUM_LANES * LANE_WIDTH)) begin
            data_buffer_d[bit_offset +: DATA_WIDTH] = axi_rdata_i;
            word_count_d = word_count_q + 1;
            bytes_remaining_d = bytes_remaining_q - (DATA_WIDTH / 8);
            bytes_transferred_d = bytes_transferred_q + (DATA_WIDTH / 8);
          end
          
          if (buffer_full || axi_rlast_i) begin
            if (data_ready_i) begin
              data_valid_o = 1'b1;
              word_count_d = '0;
              data_buffer_d = '0;
            end
          end
          
          if (transfer_complete && axi_rlast_i) begin
            if (data_ready_i || !buffer_full) begin
              if (sg_mode_q && !desc_last) begin
                state_d = NEXT_DESC;  // Load next descriptor
              end else begin
                state_d = DONE;
              end
            end
          end else if (axi_rlast_i && !transfer_complete) begin
            src_addr_d = src_addr_q + ((burst_len + 1) * (DATA_WIDTH / 8));
            state_d = READ_ADDR;
          end
        end
      end
      
      NEXT_DESC: begin
        // Simplified: Load next descriptor (would read from memory in full implementation)
        state_d = IDLE;  // Return to IDLE to load next descriptor
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
  
  assign cfg_bytes_transferred_o = bytes_transferred_q;
  
  // Sequential logic for command queue
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (int i = 0; i < CMD_QUEUE_DEPTH; i++) begin
        cmd_queue[i] <= '0;
      end
    end else if (cmd_enqueue) begin
      cmd_queue[cmd_wr_ptr_q].src_addr <= cmd_src_addr_i;
      cmd_queue[cmd_wr_ptr_q].dst_addr <= cmd_dst_addr_i;
      cmd_queue[cmd_wr_ptr_q].size <= cmd_size_i;
      cmd_queue[cmd_wr_ptr_q].valid <= 1'b1;
    end else if (cmd_dequeue) begin
      cmd_queue[cmd_rd_ptr_q].valid <= 1'b0;  // Invalidate after dequeue
    end
  end
  
  // Sequential logic
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE;
      src_addr_q <= '0;
      dst_addr_q <= '0;
      size_q <= '0;
      bytes_remaining_q <= '0;
      bytes_transferred_q <= '0;
      queue_mode_q <= 1'b0;
      sg_mode_q <= 1'b0;
      desc_addr_q <= 1'b0;
      current_desc_q <= '0;
      data_buffer_q <= '0;
      word_count_q <= '0;
      cmd_wr_ptr_q <= '0;
      cmd_rd_ptr_q <= '0;
      cmd_count_q <= '0;
      irq_done_q <= 1'b0;
      irq_error_q <= 1'b0;
    end else begin
      state_q <= state_d;
      src_addr_q <= src_addr_d;
      dst_addr_q <= dst_addr_d;
      size_q <= size_d;
      bytes_remaining_q <= bytes_remaining_d;
      bytes_transferred_q <= bytes_transferred_d;
      queue_mode_q <= queue_mode_d;
      sg_mode_q <= sg_mode_d;
      desc_addr_q <= desc_addr_d;
      current_desc_q <= current_desc_d;
      data_buffer_q <= data_buffer_d;
      word_count_q <= word_count_d;
      cmd_wr_ptr_q <= cmd_wr_ptr_d;
      cmd_rd_ptr_q <= cmd_rd_ptr_d;
      cmd_count_q <= cmd_count_d;
      irq_done_q <= irq_done_d;
      irq_error_q <= irq_error_d;
    end
  end

endmodule
