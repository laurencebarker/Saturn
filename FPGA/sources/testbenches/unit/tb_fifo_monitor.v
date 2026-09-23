`timescale 1ns / 1ps
// SOURCES: FIFO_Monitor.v
//////////////////////////////////////////////////////////////////////////////////
// Module Name:    tb_fifo_monitor
// Description:    self checking test of FIFO_Monitor
//                 - count readback, over threshold / underflow / overflow flags
//                 - threshold 0 (reset value) means "no threshold": no permanent
//                   over-threshold flag, underflow still detectable
//                 - an overflow event close to a read must never be lost
//                 - interrupt output follows enabled flags
//                 - RDATA stable under back-pressure
//////////////////////////////////////////////////////////////////////////////////

module tb_fifo_monitor;

  reg aclk = 0;
  reg aresetn = 0;
  always #4 aclk = ~aclk;

`include "axil_tb_bus.vh"

  reg  [31:0] count1 = 100, count2 = 0, count3 = 0, count4 = 0;
  reg         ovf1 = 0, ovf2 = 0, ovf3 = 0, ovf4 = 0;
  wire        int1, int2, int3, int4;

  FIFO_Monitor dut (.aclk(aclk), .aresetn(aresetn), `AXIL_SLAVE_PORTS,
    .fifo1_count(count1), .fifo1_overflow(ovf1), .fifo2_count(count2), .fifo2_overflow(ovf2),
    .fifo3_count(count3), .fifo3_overflow(ovf3), .fifo4_count(count4), .fifo4_overflow(ovf4),
    .int1_out(int1), .int2_out(int2), .int3_out(int3), .int4_out(int4));

  integer errors = 0;
  reg ok;
  reg [31:0] d, d2;
`include "tb_helpers.vh"

  integer k, lost;
  initial
  begin
    repeat(5) @(posedge aclk);
    aresetn = 1;
    repeat(5) @(posedge aclk);

    // 1. after reset, threshold 0: count 100 must not be "over threshold"
    bfm.read(16'h0000, d, ok);
    check_eq("count readback", d[15:0], 100);
    bfm.read(16'h0000, d, ok);
    check_eq("no over-threshold with threshold 0", d[30], 0);
    // underflow with threshold 0 must still be detected
    count1 = 0;
    repeat(5) @(posedge aclk);
    count1 = 50;
    repeat(5) @(posedge aclk);
    bfm.read(16'h0000, d, ok);
    check_eq("underflow detected with threshold 0", d[29], 1);

    // 2. threshold set as the software does (FIFO depth), interrupt enabled
    bfm.write(16'h0010, 32'h80000000 | 32'd200, ok);
    bfm.read(16'h0010, d, ok);
    check_eq("control readback", d, 32'h800000C8);
    bfm.read(16'h0000, d, ok);                         // clear
    repeat(5) @(posedge aclk);
    check_eq("no interrupt when idle", int1, 0);
    count1 = 250;
    repeat(5) @(posedge aclk);
    check_eq("interrupt on over threshold", int1, 1);
    count1 = 50;
    bfm.read(16'h0000, d, ok);
    check_eq("over threshold flag", d[30], 1);
    repeat(5) @(posedge aclk);
    check_eq("interrupt cleared by read", int1, 0);

    // 3. overflow pulses swept across a read: never lost
    lost = 0;
    for(k = 0; k < 16; k = k + 1)
    begin
      bfm.read(16'h0000, d, ok);
      repeat(3) @(posedge aclk);
      fork
        bfm.read(16'h0000, d, ok);
        begin repeat(k) @(posedge aclk); #1 ovf1 = 1; @(posedge aclk); #1 ovf1 = 0; end
      join
      repeat(5) @(posedge aclk);
      bfm.read(16'h0000, d2, ok);
      if(!(d[31] | d2[31])) begin lost = lost + 1; $display("%0t ERROR: overflow at offset %0d lost", $time, k); end
    end
    check_eq("overflow events lost around read", lost, 0);

    // 4. RDATA stable while count changes and RREADY is delayed
    bfm.rready_delay = 5;
    fork
      bfm.read(16'h0000, d, ok);
      begin repeat(2) @(posedge aclk); count1 = 77; end
    join
    bfm.rready_delay = 0;

    finish_test(bfm.error_count + chk.error_count);
  end

  initial begin #5_000_000; $display("ERROR: global timeout"); $display("TEST FAIL"); $finish; end
endmodule
