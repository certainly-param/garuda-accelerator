// INT8 MAC coprocessor top-level module
// Connects to CVA6 via CVXIF interface

module int8_mac_coprocessor
  import int8_mac_instr_pkg::*;
#(
    parameter  int unsigned NrRgprPorts         = 2,
    parameter  int unsigned XLEN                = 32,
    parameter  type         readregflags_t      = logic,
    parameter  type         writeregflags_t     = logic,
    parameter  type         id_t                = logic,
    parameter  type         hartid_t            = logic,
    parameter  type         x_compressed_req_t  = logic,
    parameter  type         x_compressed_resp_t = logic,
    parameter  type         x_issue_req_t       = logic,
    parameter  type         x_issue_resp_t      = logic,
    parameter  type         x_register_t        = logic,
    parameter  type         x_commit_t          = logic,
    parameter  type         x_result_t          = logic,
    parameter  type         cvxif_req_t         = logic,
    parameter  type         cvxif_resp_t        = logic,
    localparam type         registers_t         = logic [NrRgprPorts-1:0][XLEN-1:0]
) (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  cvxif_req_t  cvxif_req_i,
    output cvxif_resp_t cvxif_resp_o
);

  x_compressed_req_t  compressed_req;
  x_compressed_resp_t compressed_resp;
  logic               compressed_valid, compressed_ready;
  
  x_issue_req_t       issue_req;
  x_issue_resp_t      issue_resp;
  logic               issue_valid, issue_ready;
  
  x_register_t        register;
  logic               register_valid;
  
  registers_t         registers;
  opcode_t            opcode;
  hartid_t            issue_hartid, hartid;
  id_t                issue_id, id;
  logic [4:0]         issue_rd, rd;
  
  logic [XLEN-1:0]    result;
  logic               result_valid;
  logic               we;

  assign compressed_req    = cvxif_req_i.compressed_req;
  assign compressed_valid  = cvxif_req_i.compressed_valid;
  assign compressed_ready  = 1'b1;
  assign compressed_resp   = x_compressed_resp_t'(0);
  
  assign issue_req         = cvxif_req_i.issue_req;
  assign issue_valid       = cvxif_req_i.issue_valid;
  assign register          = cvxif_req_i.register;
  assign register_valid    = cvxif_req_i.register_valid;
  
  assign cvxif_resp_o.compressed_ready = compressed_ready;
  assign cvxif_resp_o.compressed_resp  = compressed_resp;
  assign cvxif_resp_o.issue_ready      = issue_ready;
  assign cvxif_resp_o.issue_resp       = issue_resp;
  assign cvxif_resp_o.register_ready   = cvxif_resp_o.issue_ready;

  int8_mac_decoder #(
      .copro_issue_resp_t(copro_issue_resp_t),
      .opcode_t          (opcode_t),
      .NbInstr           (NbInstr),
      .CoproInstr        (CoproInstr),
      .NrRgprPorts       (NrRgprPorts),
      .hartid_t          (hartid_t),
      .id_t              (id_t),
      .x_issue_req_t     (x_issue_req_t),
      .x_issue_resp_t    (x_issue_resp_t),
      .x_register_t      (x_register_t),
      .registers_t       (registers_t)
  ) i_int8_mac_decoder (
      .clk_i            (clk_i),
      .rst_ni           (rst_ni),
      .issue_valid_i    (issue_valid),
      .issue_req_i      (issue_req),
      .issue_ready_o    (issue_ready),
      .issue_resp_o     (issue_resp),
      .register_valid_i (register_valid),
      .register_i       (register),
      .registers_o      (registers),
      .opcode_o         (opcode),
      .hartid_o         (issue_hartid),
      .id_o             (issue_id),
      .rd_o             (issue_rd)
  );

  int8_mac_unit #(
      .XLEN      (XLEN),
      .opcode_t  (opcode_t),
      .hartid_t  (hartid_t),
      .id_t      (id_t)
  ) i_int8_mac_unit (
      .clk_i      (clk_i),
      .rst_ni     (rst_ni),
      .rs1_i      (registers[0]),
      .rs2_i      (registers[1]),
      .rd_i       (registers[0]),
      .opcode_i   (opcode),
      .hartid_i   (issue_hartid),
      .id_i       (issue_id),
      .rd_addr_i  (issue_rd),
      .result_o   (result),
      .valid_o    (result_valid),
      .we_o       (we),
      .rd_addr_o  (rd),
      .hartid_o   (hartid),
      .id_o       (id)
  );

  always_comb begin
    cvxif_resp_o.result_valid  = result_valid;
    cvxif_resp_o.result.hartid = hartid;
    cvxif_resp_o.result.id     = id;
    cvxif_resp_o.result.data   = result;
    cvxif_resp_o.result.rd     = rd;
    cvxif_resp_o.result.we     = we;
  end

endmodule
