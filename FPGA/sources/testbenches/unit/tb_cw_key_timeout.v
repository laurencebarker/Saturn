`timescale 1ns / 1ps
// SOURCES: cw_key_ramp.v
//////////////////////////////////////////////////////////////////////////////////
// Module Name:    tb_cw_key_timeout
// Description:    TX safety test of cw_key_ramp key down timeout (KEYDOWN_TIMEOUT_MS=3)
//                 - key held longer than the timeout: envelope ramps down and PTT drops
//                   while the key is still held, and stays off
//                 - after release, a new key press works normally
//                 - a key press shorter than the timeout is unaffected
//////////////////////////////////////////////////////////////////////////////////

module tb_cw_key_timeout;

  reg aclk = 0;
  reg aresetn = 0;
  always #4 aclk = ~aclk;

  localparam MS = 122880;

  reg        key_down = 0;
  wire       CW_PTT;
  wire [47:0] m0_tdata; wire m0_tvalid; reg m0_tready = 0;
  wire [15:0] m1_tdata; wire m1_tvalid;
  wire bram_rst, bram_enable; wire [31:0] bram_addr; wire [3:0] bram_web;
  reg  [31:0] bram_data = 0;
  always @(posedge aclk) bram_data <= (bram_addr >> 2) * 1000;

  cw_key_ramp #(.KEYDOWN_TIMEOUT_MS(3)) dut (.aclk(aclk), .aresetn(aresetn), .key_down(key_down),
    .delay_time(8'd0), .hang_time(10'd1), .ramp_length(13'd16), .keyer_enable(1'b1), .protocol_2(1'b1),
    .CW_PTT(CW_PTT), .m0_axis_tdata(m0_tdata), .m0_axis_tvalid(m0_tvalid), .m0_axis_tready(m0_tready),
    .m1_axis_tdata(m1_tdata), .m1_axis_tvalid(m1_tvalid), .bram_rst(bram_rst), .bram_addr(bram_addr),
    .bram_enable(bram_enable), .bram_web(bram_web), .bram_data(bram_data));

  integer tick = 0;
  always @(posedge aclk) begin tick = (tick + 1) % 64; m0_tready <= (tick == 0); end

  integer errors = 0;
`include "tb_helpers.vh"

  integer t;
  initial
  begin
    repeat(10) @(posedge aclk);
    aresetn = 1;
    repeat(10) @(posedge aclk);

    // 1. short press (2 ms) is unaffected
    key_down = 1;
    repeat(2*MS) @(posedge aclk);
    check_eq("PTT during short press", CW_PTT, 1);
    check_eq("full amplitude during short press", m0_tdata[23:0], 16*1000);
    key_down = 0;
    t = 0; while(CW_PTT && t < 5*MS) begin @(posedge aclk); t = t + 1; end
    check_eq("PTT released after short press", CW_PTT, 0);

    // 2. stuck key: held 10 ms, timeout 3 ms
    key_down = 1;
    repeat(10) @(posedge aclk);
    check_eq("PTT on for stuck key", CW_PTT, 1);
    t = 10; while(CW_PTT && t < 10*MS) begin @(posedge aclk); t = t + 1; end
    check_eq("PTT dropped while key still held", CW_PTT, 0);
    check_true("PTT dropped after timeout + hang (~4ms)", (t > 3*MS) && (t < 5*MS));
    check_eq("envelope at zero", m0_tdata[23:0], 0);
    repeat(3*MS) @(posedge aclk);
    check_eq("PTT stays off while key held", CW_PTT, 0);

    // 3. release and press again
    key_down = 0;
    repeat(100) @(posedge aclk);
    key_down = 1;
    repeat(1000) @(posedge aclk);
    check_eq("PTT works again after release", CW_PTT, 1);
    key_down = 0;

    finish_test(0);
  end

  initial begin #300_000_000; $display("ERROR: global timeout"); $display("TEST FAIL"); $finish; end
endmodule
