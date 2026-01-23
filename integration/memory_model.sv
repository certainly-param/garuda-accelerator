// Simple AXI memory model for CVA6 NoC interface
// Responds to AXI read/write requests with a simple memory array

module memory_model #(
    parameter int unsigned AxiIdWidth = 4,
    parameter int unsigned AxiAddrWidth = 64,
    parameter int unsigned AxiDataWidth = 64,
    parameter int unsigned AxiUserWidth = 32,
    parameter int unsigned MEM_SIZE = 1024*1024,  // 1MB memory
    parameter logic [AxiAddrWidth-1:0] MEM_BASE = 64'h8000_0000
) (
    input logic clk_i,
    input logic rst_ni,
    // AXI write address channel
    input logic [AxiIdWidth-1:0]   aw_id,
    input logic [AxiAddrWidth-1:0] aw_addr,
    input logic [7:0]              aw_len,
    input logic [2:0]              aw_size,
    input logic [1:0]              aw_burst,
    input logic                    aw_lock,
    input logic [3:0]              aw_cache,
    input logic [2:0]              aw_prot,
    input logic [3:0]              aw_qos,
    input logic [3:0]              aw_region,
    input logic [AxiUserWidth-1:0] aw_user,
    input logic                    aw_valid,
    output logic                   aw_ready,
    // AXI write data channel
    input logic [AxiDataWidth-1:0]     w_data,
    input logic [(AxiDataWidth/8)-1:0] w_strb,
    input logic                        w_last,
    input logic [AxiUserWidth-1:0]     w_user,
    input logic                        w_valid,
    output logic                       w_ready,
    // AXI write response channel
    output logic [AxiIdWidth-1:0]   b_id,
    output logic [1:0]              b_resp,
    output logic [AxiUserWidth-1:0] b_user,
    output logic                    b_valid,
    input logic                     b_ready,
    // AXI read address channel
    input logic [AxiIdWidth-1:0]   ar_id,
    input logic [AxiAddrWidth-1:0] ar_addr,
    input logic [7:0]              ar_len,
    input logic [2:0]              ar_size,
    input logic [1:0]              ar_burst,
    input logic                    ar_lock,
    input logic [3:0]              ar_cache,
    input logic [2:0]              ar_prot,
    input logic [3:0]              ar_qos,
    input logic [3:0]              ar_region,
    input logic [AxiUserWidth-1:0] ar_user,
    input logic                    ar_valid,
    output logic                   ar_ready,
    // AXI read data channel
    output logic [AxiIdWidth-1:0]   r_id,
    output logic [AxiDataWidth-1:0] r_data,
    output logic [1:0]              r_resp,
    output logic                    r_last,
    output logic [AxiUserWidth-1:0] r_user,
    output logic                    r_valid,
    input logic                     r_ready
);

  // Memory array - word-addressable with AxiDataWidth words
  localparam int unsigned ADDR_WIDTH = $clog2(MEM_SIZE / (AxiDataWidth/8));
  logic [AxiDataWidth-1:0] mem [0:2**ADDR_WIDTH-1];

  // Write address tracking
  logic [AxiIdWidth-1:0]   aw_id_q;
  logic [AxiAddrWidth-1:0] aw_addr_q;
  logic [7:0]              aw_len_q;
  logic [AxiUserWidth-1:0] aw_user_q;
  logic                    aw_accepted;

  // Read address tracking
  logic [AxiIdWidth-1:0]   ar_id_q;
  logic [AxiAddrWidth-1:0] ar_addr_q;
  logic [7:0]              ar_len_q;
  logic [AxiUserWidth-1:0] ar_user_q;
  logic [7:0]              read_count;
  logic                    read_active;

  // Calculate word address (byte address -> word index)
  function automatic logic [ADDR_WIDTH-1:0] byte_to_word_addr(logic [AxiAddrWidth-1:0] byte_addr);
    logic [AxiAddrWidth-1:0] offset;
    offset = byte_addr - MEM_BASE;
    return offset[AxiAddrWidth-1:($clog2(AxiDataWidth/8))];
  endfunction

  // Check if address is in range
  function automatic logic addr_in_range(logic [AxiAddrWidth-1:0] addr);
    return (addr >= MEM_BASE) && (addr < (MEM_BASE + MEM_SIZE));
  endfunction

  // Write address channel
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      aw_accepted <= 1'b0;
      aw_id_q <= '0;
      aw_addr_q <= '0;
      aw_len_q <= '0;
      aw_user_q <= '0;
    end else begin
      if (aw_valid && aw_ready) begin
        aw_accepted <= 1'b1;
        aw_id_q <= aw_id;
        aw_addr_q <= aw_addr;
        aw_len_q <= aw_len;
        aw_user_q <= aw_user;
      end else if (b_valid && b_ready) begin
        aw_accepted <= 1'b0;
      end
    end
  end

  assign aw_ready = !aw_accepted || (w_valid && w_ready && w_last);

  // Write data channel - simple implementation (no burst support yet)
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      // Memory initialization - leave as X for now
    end else begin
      if (w_valid && w_ready && aw_accepted) begin
        if (addr_in_range(aw_addr_q)) begin
          logic [ADDR_WIDTH-1:0] word_addr;
          word_addr = byte_to_word_addr(aw_addr_q);
          // Write with byte enables
          for (int i = 0; i < (AxiDataWidth/8); i++) begin
            if (w_strb[i]) begin
              mem[word_addr][i*8 +: 8] <= w_data[i*8 +: 8];
            end
          end
        end
      end
    end
  end

  assign w_ready = aw_accepted;

  // Write response channel
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      b_valid <= 1'b0;
      b_id <= '0;
      b_user <= '0;
    end else begin
      if (w_valid && w_ready && w_last) begin
        b_valid <= 1'b1;
        b_id <= aw_id_q;
        b_user <= aw_user_q;
        b_resp <= addr_in_range(aw_addr_q) ? 2'b00 : 2'b10;  // OKAY or SLVERR
      end else if (b_valid && b_ready) begin
        b_valid <= 1'b0;
      end
    end
  end

  // Read address channel
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      read_active <= 1'b0;
      ar_id_q <= '0;
      ar_addr_q <= '0;
      ar_len_q <= '0;
      ar_user_q <= '0;
      read_count <= '0;
    end else begin
      if (ar_valid && ar_ready) begin
        read_active <= 1'b1;
        ar_id_q <= ar_id;
        ar_addr_q <= ar_addr;
        ar_len_q <= ar_len;
        ar_user_q <= ar_user;
        read_count <= '0;
      end else if (r_valid && r_ready) begin
        if (r_last) begin
          read_active <= 1'b0;
          read_count <= '0;
        end else begin
          read_count <= read_count + 1;
          // Increment address for next read
          case (ar_len_q)  // Simple increment (fixed size)
            8'd0: ar_addr_q <= ar_addr_q + (AxiDataWidth/8);
            default: ar_addr_q <= ar_addr_q + (AxiDataWidth/8);
          endcase
        end
      end
    end
  end

  assign ar_ready = !read_active;

  // Read data channel - simple implementation (no burst support yet)
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      r_valid <= 1'b0;
      r_id <= '0;
      r_user <= '0;
      r_data <= '0;
      r_resp <= '0;
      r_last <= 1'b0;
    end else begin
      if (read_active) begin
        if (!r_valid || (r_valid && r_ready)) begin
          r_valid <= 1'b1;
          r_id <= ar_id_q;
          r_user <= ar_user_q;
          if (addr_in_range(ar_addr_q)) begin
            logic [ADDR_WIDTH-1:0] word_addr;
            word_addr = byte_to_word_addr(ar_addr_q);
            r_data <= mem[word_addr];
            r_resp <= 2'b00;  // OKAY
          end else begin
            r_data <= '0;
            r_resp <= 2'b10;  // SLVERR
          end
          r_last <= (read_count >= ar_len_q);
        end
      end else if (r_valid && r_ready) begin
        r_valid <= 1'b0;
      end
    end
  end

endmodule
