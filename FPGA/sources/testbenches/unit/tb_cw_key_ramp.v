`timescale 1ns / 1ps
// SOURCES: cw_key_ramp.v
//////////////////////////////////////////////////////////////////////////////////
// Module Name:    tb_cw_key_ramp
// Description:    self checking test of cw_key_ramp (CW PTT and envelope ramp)
//                 - key down: PTT immediately, ramp starts after delay_time ms,
//                   ramp reaches full amplitude and dwells
//                 - key up: delay, ramp down to zero, PTT held for hang_time ms
//                 - keyer disabled: no PTT
//                 BRAM modelled as synchronous read, ramp word n = n * 1000
//////////////////////////////////////////////////////////////////////////////////

module tb_cw_key_ramp;

  reg aclk = 0;
  reg aresetn = 0;
  always #4 aclk = ~aclk;                     // clock period is not 122.88MHz but counts are in clocks

  localparam MS = 122880;                     // clocks per ms in the design

  reg        key_down = 0, keyer_enable = 1, protocol_2 = 1;
  reg  [7:0] delay_time = 1;
  reg  [9:0] hang_time = 2;
  reg [12:0] ramp_length = 16;                // words
  wire       CW_PTT;
  wire [47:0] m0_tdata; wire m0_tvalid; reg m0_tready = 0;
  wire [15:0] m1_tdata; wire m1_tvalid;
  wire bram_rst, bram_enable; wire [31:0] bram_addr; wire [3:0] bram_web;
  reg  [31:0] bram_data = 0;
  always @(posedge aclk) bram_data <= (bram_addr >> 2) * 1000;   // synchronous read

  cw_key_ramp dut (.aclk(aclk), .aresetn(aresetn), .key_down(key_down), .delay_time(delay_time),
    .hang_time(hang_time), .ramp_length(ramp_length), .keyer_enable(keyer_enable), .protocol_2(protocol_2),
    .CW_PTT(CW_PTT), .m0_axis_tdata(m0_tdata), .m0_axis_tvalid(m0_tvalid), .m0_axis_tready(m0_tready),
    .m1_axis_tdata(m1_tdata), .m1_axis_tvalid(m1_tvalid), .bram_rst(bram_rst), .bram_addr(bram_addr),
    .bram_enable(bram_enable), .bram_web(bram_web), .bram_data(bram_data));

  // tready: one sample every 64 clocks (stands in for 192kHz)
  integer tick = 0;
  always @(posedge aclk) begin tick = (tick + 1) % 64; m0_tready <= (tick == 0); end

  integer errors = 0;
`include "tb_helpers.vh"

  integer t0, t;
  initial
  begin
    repeat(10) @(posedge aclk);
    aresetn = 1;
    repeat(10) @(posedge aclk);

    // 1. key down
    key_down = 1;
    t0 = $time;
    repeat(3) @(posedge aclk);
    check_eq("PTT on key down", CW_PTT, 1);
    t = 0;
    while(bram_addr == 0 && t < 3*MS) begin @(posedge aclk); t = t + 1; end
    check_true("ramp starts after ~delay_time ms", (t > MS - 200) && (t < MS + 200));
    t = 0;
    while(m0_tdata[23:0] != 16*1000 && t < 100000) begin @(posedge aclk); t = t + 1; end
    check_eq("ramp reaches full amplitude", m0_tdata[23:0], 16*1000);
    repeat(5000) @(posedge aclk);
    check_eq("dwell at full amplitude", m0_tdata[23:0], 16*1000);
    check_eq("PTT held while key down", CW_PTT, 1);

    // 2. key up: delay, ramp down, hang
    key_down = 0;
    repeat(MS/2) @(posedge aclk);
    check_eq("amplitude held during release delay", m0_tdata[23:0], 16*1000);
    t = 0;
    while(m0_tdata[23:0] != 0 && t < 3*MS) begin @(posedge aclk); t = t + 1; end
    check_eq("ramp down to zero", m0_tdata[23:0], 0);
    check_eq("PTT held during hang", CW_PTT, 1);
    t = 0;
    while(CW_PTT && t < 4*MS) begin @(posedge aclk); t = t + 1; end
    check_true("PTT drops after ~hang_time ms", (t > 2*MS - 3000) && (t < 2*MS + 3000));
    check_eq("PTT off", CW_PTT, 0);

    // 3. keyer disabled
    keyer_enable = 0;
    key_down = 1;
    repeat(1000) @(posedge aclk);
    check_eq("no PTT when keyer disabled", CW_PTT, 0);
    key_down = 0;
    keyer_enable = 1;

    finish_test(0);
  end

  initial begin #200_000_000; $display("ERROR: global timeout"); $display("TEST FAIL"); $finish; end
endmodule
