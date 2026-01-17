// Address Generation Unit (AGU) - Optimizes memory access patterns
// Phase 2.3 of Production Roadmap: Memory Coalescing
// Generates optimized addresses for burst transfers with spatial locality

module address_generation_unit #(
    parameter int unsigned ADDR_WIDTH      = 32,
    parameter int unsigned MAX_BURST_SIZE  = 128,  // Maximum burst size (bytes)
    parameter int unsigned BURST_ALIGN  = 32     // Burst alignment (bytes)
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,
    
    // Configuration
    input  logic                        cfg_valid_i,
    input  logic [ADDR_WIDTH-1:0]       base_addr_i,      // Base address
    input  logic [ADDR_WIDTH-1:0]       stride_i,         // Address stride (bytes)
    input  logic [15:0]                 count_i,          // Number of accesses
    input  logic [ADDR_WIDTH-1:0]       element_size_i,   // Element size (bytes)
    input  logic [2:0]                  access_pattern_i, // 0=linear, 1=strided, 2=blocked
    input  logic                        start_i,
    output logic                        cfg_ready_o,
    
    // Optimized address output
    output logic                        addr_valid_o,
    output logic [ADDR_WIDTH-1:0]       addr_o,
    output logic [7:0]                  burst_len_o,      // Burst length -1
    output logic [2:0]                  burst_size_o,     // Burst size
    output logic                        last_addr_o,      // Last address in sequence
    input  logic                        addr_ready_i,
    
    // Status
    output logic                        done_o,
    output logic [15:0]                 remaining_o       // Remaining accesses
);

  // AGU State Machine
  typedef enum logic [2:0] {
    IDLE,
    CALC_BURST,
    GEN_ADDR,
    WAIT_READY,
    DONE
  } agu_state_t;

  agu_state_t state_q, state_d;
  
  // Address and control registers
  logic [ADDR_WIDTH-1:0] base_addr_q, base_addr_d;
  logic [ADDR_WIDTH-1:0] stride_q, stride_d;
  logic [15:0]           count_q, count_d;
  logic [15:0]           remaining_q, remaining_d;
  logic [ADDR_WIDTH-1:0] current_addr_q, current_addr_d;
  logic [ADDR_WIDTH-1:0] element_size_q, element_size_d;
  logic [2:0]            pattern_q, pattern_d;
  
  // Burst optimization
  logic [7:0]            burst_len;
  logic [2:0]            burst_size;
  logic [ADDR_WIDTH-1:0] aligned_addr;
  logic                  can_coalesce;
  
  // Calculate burst parameters
  always_comb begin
    // Align address to burst boundary
    logic [ADDR_WIDTH-1:0] addr_mask;
    addr_mask = (BURST_ALIGN - 1);
    aligned_addr = (current_addr_q & ~addr_mask);  // Align to burst boundary
    
    // Calculate optimal burst size
    logic [ADDR_WIDTH-1:0] bytes_to_transfer;
    bytes_to_transfer = remaining_q * element_size_q;
    
    // Determine burst size based on element size
    if (element_size_q == 1) begin
      burst_size = 3'b000;  // 1 byte
    end else if (element_size_q == 2) begin
      burst_size = 3'b001;  // 2 bytes
    end else if (element_size_q == 4) begin
      burst_size = 3'b010;  // 4 bytes
    end else if (element_size_q == 8) begin
      burst_size = 3'b011;  // 8 bytes
    end else begin
      burst_size = 3'b010;  // Default: 4 bytes
    end
    
    // Calculate burst length (maximum based on remaining and alignment)
    logic [ADDR_WIDTH-1:0] max_burst_bytes;
    max_burst_bytes = (remaining_q * element_size_q < MAX_BURST_SIZE) ? 
                      (remaining_q * element_size_q) : MAX_BURST_SIZE;
    
    // Align to burst size
    max_burst_bytes = (max_burst_bytes & ~((1 << burst_size) - 1));
    
    // Burst length = (bytes / burst_size) - 1
    burst_len = ((max_burst_bytes >> burst_size) > 256) ? 
                255 : ((max_burst_bytes >> burst_size) - 1);
    
    // Check if we can coalesce multiple accesses
    can_coalesce = (remaining_q > 1) && 
                   (pattern_q == 3'b000) &&  // Linear pattern only
                   ((current_addr_q & addr_mask) == 0);  // Aligned
  end
  
  // State machine
  always_comb begin
    state_d = state_q;
    base_addr_d = base_addr_q;
    stride_d = stride_q;
    count_d = count_q;
    remaining_d = remaining_q;
    current_addr_d = current_addr_q;
    element_size_d = element_size_q;
    pattern_d = pattern_q;
    
    cfg_ready_o = 1'b0;
    addr_valid_o = 1'b0;
    addr_o = aligned_addr;
    burst_len_o = burst_len;
    burst_size_o = burst_size;
    last_addr_o = 1'b0;
    done_o = 1'b0;
    remaining_o = remaining_q;
    
    case (state_q)
      IDLE: begin
        cfg_ready_o = 1'b1;
        if (cfg_valid_i && start_i) begin
          base_addr_d = base_addr_i;
          stride_d = stride_i;
          count_d = count_i;
          remaining_d = count_i;
          current_addr_d = base_addr_i;
          element_size_d = element_size_i;
          pattern_d = access_pattern_i;
          state_d = CALC_BURST;
        end
      end
      
      CALC_BURST: begin
        state_d = GEN_ADDR;
      end
      
      GEN_ADDR: begin
        addr_valid_o = 1'b1;
        addr_o = aligned_addr;
        burst_len_o = burst_len;
        burst_size_o = burst_size;
        last_addr_o = (remaining_q <= (burst_len + 1));
        
        if (addr_ready_i) begin
          // Update address based on pattern
          case (pattern_q)
            3'b000: begin  // Linear
              logic [ADDR_WIDTH-1:0] bytes_transferred;
              bytes_transferred = (burst_len + 1) << burst_size;
              current_addr_d = current_addr_q + bytes_transferred;
              remaining_d = remaining_q - ((burst_len + 1));
            end
            
            3'b001: begin  // Strided
              current_addr_d = current_addr_q + stride_q;
              remaining_d = remaining_q - 1;
            end
            
            default: begin  // Default: linear
              current_addr_d = current_addr_q + element_size_q;
              remaining_d = remaining_q - 1;
            end
          endcase
          
          if (remaining_d == 0) begin
            state_d = DONE;
          end else begin
            state_d = CALC_BURST;
          end
        end
      end
      
      DONE: begin
        done_o = 1'b1;
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
      base_addr_q <= '0;
      stride_q <= '0;
      count_q <= '0;
      remaining_q <= '0;
      current_addr_q <= '0;
      element_size_q <= '0;
      pattern_q <= '0;
    end else begin
      state_q <= state_d;
      base_addr_q <= base_addr_d;
      stride_q <= stride_d;
      count_q <= count_d;
      remaining_q <= remaining_d;
      current_addr_q <= current_addr_d;
      element_size_q <= element_size_d;
      pattern_q <= pattern_d;
    end
  end

endmodule
