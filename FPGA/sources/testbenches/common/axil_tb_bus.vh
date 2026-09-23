//////////////////////////////////////////////////////////////////////////////////
// common AXI4-Lite bus for unit tests: `include inside the tb module after
// declaring aclk and aresetn. Provides bfm (master), chk (protocol checker)
// and the macro `AXIL_SLAVE_PORTS for connecting a standard s_axi_* slave.
// define AXIL_ADDR_W / AXIL_DATA_W before including to override widths.
//////////////////////////////////////////////////////////////////////////////////
`ifndef AXIL_ADDR_W
`define AXIL_ADDR_W 16
`endif
`ifndef AXIL_DATA_W
`define AXIL_DATA_W 32
`endif
  wire [`AXIL_ADDR_W-1:0] awaddr, araddr;
  wire awvalid, awready, wvalid, wready, bvalid, bready, arvalid, arready, rvalid, rready;
  wire [`AXIL_DATA_W-1:0] wdata, rdata;
  wire [`AXIL_DATA_W/8-1:0] wstrb;
  wire [1:0] bresp, rresp;

  axil_master_bfm #(.ADDR_WIDTH(`AXIL_ADDR_W), .DATA_WIDTH(`AXIL_DATA_W)) bfm (
    .aclk(aclk), .awaddr(awaddr), .awvalid(awvalid), .awready(awready), .wdata(wdata), .wstrb(wstrb),
    .wvalid(wvalid), .wready(wready), .bresp(bresp), .bvalid(bvalid), .bready(bready),
    .araddr(araddr), .arvalid(arvalid), .arready(arready), .rdata(rdata), .rresp(rresp),
    .rvalid(rvalid), .rready(rready));

  axil_checker #(.DATA_WIDTH(`AXIL_DATA_W)) chk (
    .aclk(aclk), .aresetn(aresetn), .awready(awready), .wready(wready), .bvalid(bvalid), .bready(bready),
    .arready(arready), .rdata(rdata), .rresp(rresp), .rvalid(rvalid), .rready(rready));

`define AXIL_SLAVE_PORTS \
    .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready), \
    .s_axi_wdata(wdata), .s_axi_wvalid(wvalid), .s_axi_wready(wready), \
    .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready), \
    .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready), \
    .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready)
