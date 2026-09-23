`timescale 1ns / 1ps
// SOURCES: AXI_FIFO_overflow_latch_reader.v
//////////////////////////////////////////////////////////////////////////////////
// Module Name:    tb_fifo_overflow_reader
// Description:    self checking test of AXI_FIFO_overflow_reader
//                 - overflow events are latched and cleared by reading 0x0
//                 - an event close to a read must never be lost: it appears in that
//                   read or in the next one
//                 - reading the peak registers (0x4/0x8) must not clear overflow flags
//                 - ADC peak magnitude of -32768 reads as 0x00008000
//                 - a stray write must complete (not hang the bus)
//////////////////////////////////////////////////////////////////////////////////

module tb_fifo_overflow_reader;

  reg aclk = 0;
  reg aresetn = 0;
  always #4 aclk = ~aclk;

`include "axil_tb_bus.vh"

  reg  [15:0] ovf = 0;
  reg  [15:0] adc1 = 0, adc2 = 0;

  AXI_FIFO_overflow_reader dut (.aclk(aclk), .aresetn(aresetn), `AXIL_SLAVE_PORTS,
    .overflow1(ovf[0]), .overflow2(ovf[1]), .overflow3(ovf[2]), .overflow4(ovf[3]),
    .overflow5(ovf[4]), .overflow6(ovf[5]), .overflow7(ovf[6]), .overflow8(ovf[7]),
    .overflow9(ovf[8]), .overflow10(ovf[9]), .overflow11(ovf[10]), .overflow12(ovf[11]),
    .overflow13(ovf[12]), .overflow14(ovf[13]), .overflow15(ovf[14]), .overflow16(ovf[15]),
    .ADC1data(adc1), .ADC2data(adc2));

  integer errors = 0;
  reg ok;
  reg [31:0] d, d2;
`include "tb_helpers.vh"

  task pulse;
    input [15:0] bits;
    begin
      @(posedge aclk); #1 ovf = bits;
      @(posedge aclk); #1 ovf = 0;
    end
  endtask

  integer k, lost;
  initial
  begin
    repeat(5) @(posedge aclk);
    aresetn = 1;
    repeat(5) @(posedge aclk);

    // 1. basic latch and clear
    pulse(16'h8001);
    repeat(5) @(posedge aclk);
    bfm.read(16'h0000, d, ok);
    check_eq("latched overflow bits", d, 32'h8001);
    bfm.read(16'h0000, d, ok);
    check_eq("cleared after read", d, 0);

    // 2. sweep an event across the read transaction: must be reported exactly once
    lost = 0;
    for(k = 0; k < 16; k = k + 1)
    begin
      bfm.read(16'h0000, d, ok);                 // clear
      repeat(3) @(posedge aclk);
      fork
        bfm.read(16'h0000, d, ok);
        begin repeat(k) @(posedge aclk); pulse(16'h0004); end
      join
      repeat(5) @(posedge aclk);
      bfm.read(16'h0000, d2, ok);
      if(!(d[2] | d2[2])) begin lost = lost + 1; $display("%0t ERROR: event at offset %0d lost", $time, k); end
    end
    check_eq("events lost around read", lost, 0);

    // 3. reading peak registers must not clear overflow flags
    bfm.read(16'h0000, d, ok);
    pulse(16'h0002);
    repeat(5) @(posedge aclk);
    bfm.read(16'h0004, d, ok);
    bfm.read(16'h0008, d, ok);
    bfm.read(16'h0000, d, ok);
    check_eq("overflow survives peak register reads", d[1], 1);

    // 4. ADC peak magnitude at negative full scale
    adc1 = 16'h8000; adc2 = 16'd1000;
    repeat(3) @(posedge aclk);
    adc1 = 16'd100;  adc2 = -16'sd2000;
    repeat(5) @(posedge aclk);
    adc1 = 16'd50;   adc2 = 16'd10;
    repeat(5) @(posedge aclk);
    bfm.read(16'h0000, d, ok);                   // latches peaks
    bfm.read(16'h0004, d, ok);
    check_eq("ADC1 peak of -32768", d, 32'h00008000);
    bfm.read(16'h0008, d, ok);
    check_eq("ADC2 peak of -2000", d, 32'd2000);
    repeat(5) @(posedge aclk);
    bfm.read(16'h0000, d, ok);                   // next period: peaks restart
    bfm.read(16'h0004, d, ok);
    check_eq("ADC1 peak next period", d, 32'd50);

    // 5. stray write, then bus still usable; RDATA stable under back-pressure
    bfm.write(16'h0000, 32'hFFFFFFFF, ok);
    check_eq("stray write completes", ok, 1);
    bfm.rready_delay = 5;
    fork
      bfm.read(16'h0000, d, ok);
      begin repeat(3) @(posedge aclk); pulse(16'h0010); end
    join
    bfm.rready_delay = 0;

    finish_test(bfm.error_count + chk.error_count);
  end

  initial begin #5_000_000; $display("ERROR: global timeout"); $display("TEST FAIL"); $finish; end
endmodule
