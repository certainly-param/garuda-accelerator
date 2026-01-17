// Testbench for DMA Engine
// Tests AXI read interface and wide data packing

`timescale 1ns / 1ps

module tb_dma_engine;

  parameter int unsigned DATA_WIDTH = 32;
  parameter int unsigned ADDR_WIDTH = 32;
  parameter int unsigned NUM_LANES = 16;
  parameter int unsigned LANE_WIDTH = 32;

  logic clk, rst_n;
  
  // DMA configuration
  logic cfg_valid, cfg_start;
  logic [ADDR_WIDTH-1:0] cfg_src_addr, cfg_dst_addr, cfg_size;
  logic cfg_ready, cfg_done, cfg_error;
  
  // AXI interface
  logic axi_arvalid, axi_arready;
  logic [ADDR_WIDTH-1:0] axi_araddr;
  logic [7:0] axi_arlen;
  logic [2:0] axi_arsize;
  logic [1:0] axi_arburst;
  
  logic axi_rvalid, axi_rready;
  logic [DATA_WIDTH-1:0] axi_rdata;
  logic axi_rlast;
  
  // Data output
  logic data_valid, data_ready;
  logic [NUM_LANES*LANE_WIDTH-1:0] data_out;
  logic busy;
  
  // Memory model (simple AXI memory)
  logic [DATA_WIDTH-1:0] mem [1024:0];
  
  // Clock generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk;  // 10ns period = 100MHz
  end
  
  // Reset generation
  initial begin
    rst_n = 0;
    #50;
    rst_n = 1;
  end
  
  // Instantiate DMA engine
  dma_engine #(
      .DATA_WIDTH(DATA_WIDTH),
      .ADDR_WIDTH(ADDR_WIDTH),
      .NUM_LANES(NUM_LANES),
      .LANE_WIDTH(LANE_WIDTH)
  ) dut (
      .clk_i(clk),
      .rst_ni(rst_n),
      .cfg_valid_i(cfg_valid),
      .cfg_src_addr_i(cfg_src_addr),
      .cfg_dst_addr_i(cfg_dst_addr),
      .cfg_size_i(cfg_size),
      .cfg_start_i(cfg_start),
      .cfg_ready_o(cfg_ready),
      .cfg_done_o(cfg_done),
      .cfg_error_o(cfg_error),
      .axi_arvalid_o(axi_arvalid),
      .axi_arready_i(axi_arready),
      .axi_araddr_o(axi_araddr),
      .axi_arlen_o(axi_arlen),
      .axi_arsize_o(axi_arsize),
      .axi_arburst_o(axi_arburst),
      .axi_rvalid_i(axi_rvalid),
      .axi_rready_o(axi_rready),
      .axi_rdata_i(axi_rdata),
      .axi_rlast_i(axi_rlast),
      .data_valid_o(data_valid),
      .data_ready_i(data_ready),
      .data_o(data_out),
      .busy_o(busy)
  );
  
  // AXI memory model
  initial begin
    // Initialize memory with test data
    for (int i = 0; i < 1024; i++) begin
      mem[i] = i;  // Simple pattern
    end
  end
  
  // AXI read address channel
  logic [ADDR_WIDTH-1:0] read_addr;
  logic [7:0] burst_len;
  logic [3:0] beat_count;
  
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      axi_arready <= 1'b0;
      axi_rvalid <= 1'b0;
      axi_rlast <= 1'b0;
      beat_count <= '0;
    end else begin
      // Address channel
      if (axi_arvalid && !axi_arready) begin
        axi_arready <= 1'b1;
        read_addr <= axi_araddr;
        burst_len <= axi_arlen;
        beat_count <= '0;
      end else begin
        axi_arready <= 1'b0;
      end
      
      // Data channel
      if (axi_arready && axi_arvalid) begin
        axi_rvalid <= 1'b1;
        axi_rdata <= mem[read_addr[11:2]];  // Simple address mapping
      end else if (axi_rvalid && axi_rready) begin
        beat_count <= beat_count + 1;
        if (beat_count >= burst_len) begin
          axi_rlast <= 1'b1;
          axi_rvalid <= 1'b0;
        end else begin
          read_addr <= read_addr + (DATA_WIDTH / 8);
          axi_rdata <= mem[read_addr[11:2] + 1];
        end
      end else if (axi_rlast) begin
        axi_rlast <= 1'b0;
      end
    end
  end
  
  // Test stimulus
  initial begin
    $display("========================================");
    $display("DMA Engine Testbench");
    $display("========================================\n");
    
    // Initialize
    cfg_valid = 0;
    cfg_start = 0;
    cfg_src_addr = 0;
    cfg_dst_addr = 0;
    cfg_size = 0;
    data_ready = 1;
    
    @(posedge rst_n);
    #20;
    
    // Test 1: Simple transfer (64 bytes = 16 words)
    $display("[TEST 1] Transfer 64 bytes (16 words)");
    cfg_src_addr = 32'h0000_1000;
    cfg_dst_addr = 32'h0000_2000;
    cfg_size = 64;
    cfg_valid = 1;
    cfg_start = 1;
    @(posedge clk);
    cfg_start = 0;
    
    // Wait for completion
    wait (cfg_done || cfg_error);
    if (cfg_done)
      $display("  PASS: DMA transfer completed");
    else
      $display("  FAIL: DMA transfer error");
    
    #100;
    
    // Test 2: Wide data packing (512 bytes for 16 lanes)
    $display("\n[TEST 2] Transfer 512 bytes for 16 lanes");
    cfg_src_addr = 32'h0000_2000;
    cfg_dst_addr = 0;
    cfg_size = 512;  // 16 lanes × 32 bytes
    cfg_start = 1;
    @(posedge clk);
    cfg_start = 0;
    
    wait (cfg_done || cfg_error);
    if (cfg_done && data_valid)
      $display("  PASS: Wide data transfer completed");
    else
      $display("  FAIL: Wide data transfer failed");
    
    #100;
    
    $display("\n========================================");
    $display("Testbench completed");
    $display("========================================");
    $finish;
  end
  
  // Monitor
  always @(posedge clk) begin
    if (data_valid && data_ready) begin
      $display("[%0t] DMA output: %0d words ready", $time, NUM_LANES*LANE_WIDTH/DATA_WIDTH);
    end
  end

endmodule
