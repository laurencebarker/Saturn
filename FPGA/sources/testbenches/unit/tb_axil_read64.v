`timescale 1ns / 1ps
// SOURCES: axil_read64_reg.v
//////////////////////////////////////////////////////////////////////////////////
// Module Name:    tb_axil_read64
// Description:    self checking test of AXIL_ReadReg_64
//                 - reads of 0x0 / 0x4 return readdata0 / readdata1
//                 - a stray write must complete (not hang the bus)
//                 - RDATA must stay stable under back-pressure while inputs change
//////////////////////////////////////////////////////////////////////////////////

module tb_axil_read64;

  reg aclk = 0;
  reg aresetn = 0;
  always #4 aclk = ~aclk;

`include "axil_tb_bus.vh"

  reg [31:0] readdata0 = 32'h11111111, readdata1 = 32'h22222222;
  AXIL_ReadReg_64 dut (.aclk(aclk), .aresetn(aresetn), `AXIL_SLAVE_PORTS,
                       .readdata0(readdata0), .readdata1(readdata1));

  integer errors = 0;
  reg ok;
  reg [31:0] d;
`include "tb_helpers.vh"

  // live inputs: readdata1 changes every clock (like a counter)
  reg count_en = 0;
  always @(posedge aclk) if(count_en) readdata1 <= readdata1 + 1;

  initial
  begin
    repeat(10) @(posedge aclk);
    aresetn = 1;
    repeat(5) @(posedge aclk);

    bfm.read(16'h0000, d, ok);
    check_eq("read 0x0", d, 32'h11111111);
    bfm.read(16'h0004, d, ok);
    check_eq("read 0x4", d, 32'h22222222);

    bfm.write(16'h0000, 32'hFFFFFFFF, ok);
    check_eq("stray write completes", ok, 1);
    bfm.read(16'h0000, d, ok);
    check_eq("read 0x0 after write", d, 32'h11111111);

    count_en = 1;
    bfm.rready_delay = 6;
    bfm.read(16'h0004, d, ok);             // chk flags RDATA instability
    bfm.rready_delay = 0;
    count_en = 0;

    finish_test(bfm.error_count + chk.error_count);
  end

  initial begin #1_000_000; $display("ERROR: global timeout"); $display("TEST FAIL"); $finish; end
endmodule
