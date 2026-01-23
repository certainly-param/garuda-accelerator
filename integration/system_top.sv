// System top-level module integrating CVA6 RISC-V CPU with Garuda INT8 MAC coprocessor
// Implements Phase 3 of CVA6 Integration Plan
//
// This module wires CVA6 and Garuda together via the CVXIF interface.
// Memory is connected via NoC interface to enable instruction fetch and data access.

`include "rvfi_types.svh"
`include "cvxif_types.svh"

module system_top
  import ariane_pkg::*;
  import int8_mac_instr_pkg::*;
  import cva6_config_pkg::*;
  import config_pkg::*;
  import build_config_pkg::*;
#(
    // CVA6 configuration - using cv32a60x as base (32-bit, CVXIF enabled)
    parameter config_pkg::cva6_cfg_t CVA6Cfg = build_config_pkg::build_config(
        cva6_config_pkg::cva6_cfg
    )
) (
    // Clock and reset
    input  logic        clk_i,
    input  logic        rst_ni,
    // Boot configuration
    input  logic [CVA6Cfg.VLEN-1:0] boot_addr_i,
    input  logic [CVA6Cfg.XLEN-1:0] hart_id_i,
    // Interrupts
    input  logic [1:0]  irq_i,
    input  logic        ipi_i,
    input  logic        time_irq_i,
    input  logic        debug_req_i
);

  // Extract CVXIF type parameters from CVA6Cfg
  // These are derived in build_config_pkg::build_config
  localparam type readregflags_t = `READREGFLAGS_T(CVA6Cfg);
  localparam type writeregflags_t = `WRITEREGFLAGS_T(CVA6Cfg);
  localparam type id_t = `ID_T(CVA6Cfg);
  localparam type hartid_t = `HARTID_T(CVA6Cfg);
  localparam type x_compressed_req_t = `X_COMPRESSED_REQ_T(CVA6Cfg, hartid_t);
  localparam type x_compressed_resp_t = `X_COMPRESSED_RESP_T(CVA6Cfg);
  localparam type x_issue_req_t = `X_ISSUE_REQ_T(CVA6Cfg, hartid_t, id_t);
  localparam type x_issue_resp_t = `X_ISSUE_RESP_T(CVA6Cfg, writeregflags_t, readregflags_t);
  localparam type x_register_t = `X_REGISTER_T(CVA6Cfg, hartid_t, id_t, readregflags_t);
  localparam type x_commit_t = `X_COMMIT_T(CVA6Cfg, hartid_t, id_t);
  localparam type x_result_t = `X_RESULT_T(CVA6Cfg, hartid_t, id_t, writeregflags_t);
  localparam type cvxif_req_t = `CVXIF_REQ_T(CVA6Cfg, x_compressed_req_t, x_issue_req_t, x_register_t, x_commit_t);
  localparam type cvxif_resp_t = `CVXIF_RESP_T(CVA6Cfg, x_compressed_resp_t, x_issue_resp_t, x_result_t);

  // AXI types for NoC interface (matching CVA6's parameterized types)
  typedef struct packed {
    logic [CVA6Cfg.AxiIdWidth-1:0]   id;
    logic [CVA6Cfg.AxiAddrWidth-1:0] addr;
    axi_pkg::len_t                   len;
    axi_pkg::size_t                  size;
    axi_pkg::burst_t                 burst;
    logic                            lock;
    axi_pkg::cache_t                 cache;
    axi_pkg::prot_t                  prot;
    axi_pkg::qos_t                   qos;
    axi_pkg::region_t                region;
    axi_pkg::atop_t                  atop;
    logic [CVA6Cfg.AxiUserWidth-1:0] user;
  } axi_aw_chan_t;
  typedef struct packed {
    logic [CVA6Cfg.AxiDataWidth-1:0]     data;
    logic [(CVA6Cfg.AxiDataWidth/8)-1:0] strb;
    logic                                last;
    logic [CVA6Cfg.AxiUserWidth-1:0]     user;
  } axi_w_chan_t;
  typedef struct packed {
    logic [CVA6Cfg.AxiIdWidth-1:0]   id;
    logic [CVA6Cfg.AxiAddrWidth-1:0] addr;
    axi_pkg::len_t                   len;
    axi_pkg::size_t                  size;
    axi_pkg::burst_t                 burst;
    logic                            lock;
    axi_pkg::cache_t                 cache;
    axi_pkg::prot_t                  prot;
    axi_pkg::qos_t                   qos;
    axi_pkg::region_t                region;
    logic [CVA6Cfg.AxiUserWidth-1:0] user;
  } axi_ar_chan_t;
  typedef struct packed {
    logic [CVA6Cfg.AxiIdWidth-1:0]   id;
    axi_pkg::resp_t                  resp;
    logic [CVA6Cfg.AxiUserWidth-1:0] user;
  } b_chan_t;
  typedef struct packed {
    logic [CVA6Cfg.AxiIdWidth-1:0]   id;
    logic [CVA6Cfg.AxiDataWidth-1:0] data;
    axi_pkg::resp_t                  resp;
    logic                            last;
    logic [CVA6Cfg.AxiUserWidth-1:0] user;
  } r_chan_t;
  typedef struct packed {
    axi_aw_chan_t aw;
    logic         aw_valid;
    axi_w_chan_t  w;
    logic         w_valid;
    logic         b_ready;
    axi_ar_chan_t ar;
    logic         ar_valid;
    logic         r_ready;
  } noc_req_t;
  typedef struct packed {
    logic    aw_ready;
    logic    ar_ready;
    logic    w_ready;
    logic    b_valid;
    b_chan_t b;
    logic    r_valid;
    r_chan_t r;
  } noc_resp_t;

  // CVXIF interface signals - connect CVA6 <-> Garuda
  cvxif_req_t  cvxif_req;
  cvxif_resp_t cvxif_resp;

  // NoC interface signals (connected to memory model)
  noc_req_t  noc_req;
  noc_resp_t noc_resp;

  // RVFI probes (can be left unconnected if not used)
  typedef struct packed {
    logic [0:0][CVA6Cfg.XLEN-1:0] csr;
    logic [0:0][CVA6Cfg.XLEN-1:0] instr;
  } rvfi_probes_t;
  rvfi_probes_t rvfi_probes;

  // ------------------------
  // CVA6 CPU Instance
  // ------------------------
  // Note: CVA6 requires AXI channel types and NoC types as parameters
  // For now, these are left as defaults matching CVA6's expectations
  cva6 #(
      .CVA6Cfg(CVA6Cfg),
      .readregflags_t(readregflags_t),
      .writeregflags_t(writeregflags_t),
      .id_t(id_t),
      .hartid_t(hartid_t),
      .x_compressed_req_t(x_compressed_req_t),
      .x_compressed_resp_t(x_compressed_resp_t),
      .x_issue_req_t(x_issue_req_t),
      .x_issue_resp_t(x_issue_resp_t),
      .x_register_t(x_register_t),
      .x_commit_t(x_commit_t),
      .x_result_t(x_result_t),
      .cvxif_req_t(cvxif_req_t),
      .cvxif_resp_t(cvxif_resp_t),
      .axi_ar_chan_t(axi_ar_chan_t),
      .axi_aw_chan_t(axi_aw_chan_t),
      .axi_w_chan_t(axi_w_chan_t),
      .b_chan_t(b_chan_t),
      .r_chan_t(r_chan_t),
      .noc_req_t(noc_req_t),
      .noc_resp_t(noc_resp_t)
  ) i_cva6 (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .boot_addr_i(boot_addr_i),
      .hart_id_i(hart_id_i),
      .irq_i(irq_i),
      .ipi_i(ipi_i),
      .time_irq_i(time_irq_i),
      .debug_req_i(debug_req_i),
      .rvfi_probes_o(rvfi_probes),
      // CVXIF interface - connected to Garuda
      .cvxif_req_o(cvxif_req),
      .cvxif_resp_i(cvxif_resp),
      // NoC (memory) interface - will be connected to memory model in Phase 3
      .noc_req_o(noc_req),
      .noc_resp_i(noc_resp)
  );

  // ------------------------
  // Garuda INT8 MAC Coprocessor
  // ------------------------
  // Garuda expects 2 register file ports (NrRgprPorts = 2)
  localparam int unsigned GARUDA_NR_RGPR_PORTS = 2;

  int8_mac_coprocessor #(
      .NrRgprPorts(GARUDA_NR_RGPR_PORTS),
      .XLEN(CVA6Cfg.XLEN),
      .readregflags_t(readregflags_t),
      .writeregflags_t(writeregflags_t),
      .id_t(id_t),
      .hartid_t(hartid_t),
      .x_compressed_req_t(x_compressed_req_t),
      .x_compressed_resp_t(x_compressed_resp_t),
      .x_issue_req_t(x_issue_req_t),
      .x_issue_resp_t(x_issue_resp_t),
      .x_register_t(x_register_t),
      .x_commit_t(x_commit_t),
      .x_result_t(x_result_t),
      .cvxif_req_t(cvxif_req_t),
      .cvxif_resp_t(cvxif_resp_t)
  ) i_garuda (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .cvxif_req_i(cvxif_req),
      .cvxif_resp_o(cvxif_resp)
  );

  // ------------------------
  // Memory Model (Phase 3)
  // ------------------------
  // Simple AXI memory model connected to CVA6's NoC interface
  // Supports instruction and data memory
  // Unpack NoC struct to individual signals for memory model
  memory_model #(
      .AxiIdWidth(CVA6Cfg.AxiIdWidth),
      .AxiAddrWidth(CVA6Cfg.AxiAddrWidth),
      .AxiDataWidth(CVA6Cfg.AxiDataWidth),
      .AxiUserWidth(CVA6Cfg.AxiUserWidth),
      .MEM_SIZE(1024*1024),  // 1MB memory
      .MEM_BASE(64'h8000_0000)
  ) i_memory (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      // Write address channel - unpack from noc_req.aw
      .aw_id(noc_req.aw.id),
      .aw_addr(noc_req.aw.addr),
      .aw_len(noc_req.aw.len),
      .aw_size(noc_req.aw.size),
      .aw_burst(noc_req.aw.burst),
      .aw_lock(noc_req.aw.lock),
      .aw_cache(noc_req.aw.cache),
      .aw_prot(noc_req.aw.prot),
      .aw_qos(noc_req.aw.qos),
      .aw_region(noc_req.aw.region),
      .aw_user(noc_req.aw.user),
      .aw_valid(noc_req.aw_valid),
      .aw_ready(noc_resp.aw_ready),
      // Write data channel - unpack from noc_req.w
      .w_data(noc_req.w.data),
      .w_strb(noc_req.w.strb),
      .w_last(noc_req.w.last),
      .w_user(noc_req.w.user),
      .w_valid(noc_req.w_valid),
      .w_ready(noc_resp.w_ready),
      // Write response channel - pack into noc_resp.b
      .b_id(noc_resp.b.id),
      .b_resp(noc_resp.b.resp),
      .b_user(noc_resp.b.user),
      .b_valid(noc_resp.b_valid),
      .b_ready(noc_req.b_ready),
      // Read address channel - unpack from noc_req.ar
      .ar_id(noc_req.ar.id),
      .ar_addr(noc_req.ar.addr),
      .ar_len(noc_req.ar.len),
      .ar_size(noc_req.ar.size),
      .ar_burst(noc_req.ar.burst),
      .ar_lock(noc_req.ar.lock),
      .ar_cache(noc_req.ar.cache),
      .ar_prot(noc_req.ar.prot),
      .ar_qos(noc_req.ar.qos),
      .ar_region(noc_req.ar.region),
      .ar_user(noc_req.ar.user),
      .ar_valid(noc_req.ar_valid),
      .ar_ready(noc_resp.ar_ready),
      // Read data channel - pack into noc_resp.r
      .r_id(noc_resp.r.id),
      .r_data(noc_resp.r.data),
      .r_resp(noc_resp.r.resp),
      .r_last(noc_resp.r.last),
      .r_user(noc_resp.r.user),
      .r_valid(noc_resp.r_valid),
      .r_ready(noc_req.r_ready)
  );

endmodule
