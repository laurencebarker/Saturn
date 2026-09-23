`timescale 1ns / 1ps
// SOURCES: axil_config256_reg.v axil_config64_reg.v
//////////////////////////////////////////////////////////////////////////////////
// Module Name:    tb_axil_config
// Description:    self checking test of AXIL_ConfigReg_256 and AXIL_ConfigReg_64
//                 - initial values after reset
//                 - write / read back of every register, outputs follow writes
//                 - reads and writes interleaved; RREADY / BREADY back-pressure
//////////////////////////////////////////////////////////////////////////////////

module tb_axil_config;

  reg aclk = 0;
  reg aresetn = 0;
  always #4 aclk = ~aclk;

`include "axil_tb_bus.vh"

  wire [31:0] c [0:7];
  AXIL_ConfigReg_256 #(.INITIAL_VALUE_word_0(32'h11), .INITIAL_VALUE_word_7(32'h77)) dut256 (
    .aclk(aclk), .aresetn(aresetn), `AXIL_SLAVE_PORTS,
    .config_reg0(c[0]), .config_reg1(c[1]), .config_reg2(c[2]), .config_reg3(c[3]),
    .config_reg4(c[4]), .config_reg5(c[5]), .config_reg6(c[6]), .config_reg7(c[7]));

  // second bus for the 64 bit register
  wire [15:0] awaddr2, araddr2;
  wire awvalid2, awready2, wvalid2, wready2, bvalid2, bready2, arvalid2, arready2, rvalid2, rready2;
  wire [31:0] wdata2, rdata2; wire [3:0] wstrb2; wire [1:0] bresp2, rresp2;
  axil_master_bfm bfm2 (.aclk(aclk), .awaddr(awaddr2), .awvalid(awvalid2), .awready(awready2),
    .wdata(wdata2), .wstrb(wstrb2), .wvalid(wvalid2), .wready(wready2), .bresp(bresp2), .bvalid(bvalid2),
    .bready(bready2), .araddr(araddr2), .arvalid(arvalid2), .arready(arready2), .rdata(rdata2),
    .rresp(rresp2), .rvalid(rvalid2), .rready(rready2));
  axil_checker chk2 (.aclk(aclk), .aresetn(aresetn), .awready(awready2), .wready(wready2), .bvalid(bvalid2),
    .bready(bready2), .arready(arready2), .rdata(rdata2), .rresp(rresp2), .rvalid(rvalid2), .rready(rready2));
  wire [31:0] d0, d1;
  AXIL_ConfigReg_64 #(.INITIAL_VALUE_word_0(32'hAA), .INITIAL_VALUE_word_1(32'hBB)) dut64 (
    .aclk(aclk), .aresetn(aresetn),
    .s_axi_awaddr(awaddr2), .s_axi_awvalid(awvalid2), .s_axi_awready(awready2),
    .s_axi_wdata(wdata2), .s_axi_wvalid(wvalid2), .s_axi_wready(wready2),
    .s_axi_bresp(bresp2), .s_axi_bvalid(bvalid2), .s_axi_bready(bready2),
    .s_axi_araddr(araddr2), .s_axi_arvalid(arvalid2), .s_axi_arready(arready2),
    .s_axi_rdata(rdata2), .s_axi_rresp(rresp2), .s_axi_rvalid(rvalid2), .s_axi_rready(rready2),
    .config_reg0(d0), .config_reg1(d1));

  integer errors = 0;
  reg ok;
  reg [31:0] d;
`include "tb_helpers.vh"

  integer i;
  initial
  begin
    repeat(5) @(posedge aclk);
    aresetn = 1;
    repeat(5) @(posedge aclk);

    check_eq("256 initial word 0", c[0], 32'h11);
    check_eq("256 initial word 7", c[7], 32'h77);
    check_eq("64 initial word 0", d0, 32'hAA);
    check_eq("64 initial word 1", d1, 32'hBB);

    for(i = 0; i < 8; i = i + 1)
      bfm.write(i*4, 32'hC0DE0000 + i, ok);
    bfm.rready_delay = 3;
    bfm.bready_delay = 2;
    for(i = 0; i < 8; i = i + 1)
    begin
      bfm.read(i*4, d, ok);
      check_eq("256 readback", d, 32'hC0DE0000 + i);
      check_eq("256 output", c[i], 32'hC0DE0000 + i);
    end
    // interleave: write while read of another register is being held off
    fork
      bfm.read(16'h0004, d, ok);
      begin repeat(1) @(posedge aclk); end
    join
    check_eq("256 readback during interleave", d, 32'hC0DE0001);

    bfm2.write(16'h0000, 32'h12345678, ok);
    bfm2.write(16'h0004, 32'h9ABCDEF0, ok);
    bfm2.rready_delay = 4;
    bfm2.read(16'h0000, d, ok);
    check_eq("64 readback 0", d, 32'h12345678);
    bfm2.read(16'h0004, d, ok);
    check_eq("64 readback 1", d, 32'h9ABCDEF0);
    check_eq("64 outputs", {d1, d0}, 64'h9ABCDEF0_12345678);

    finish_test(bfm.error_count + chk.error_count + bfm2.error_count + chk2.error_count);
  end

  initial begin #1_000_000; $display("ERROR: global timeout"); $display("TEST FAIL"); $finish; end
endmodule
