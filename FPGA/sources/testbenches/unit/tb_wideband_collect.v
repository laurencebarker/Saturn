`timescale 1ns / 1ps
// SOURCES: wideband_collect.v
//////////////////////////////////////////////////////////////////////////////////
// Module Name:    tb_wideband_collect
// Description:    self checking test of Wideband_Collect
//                 - records depth+1 64 bit words of 4 consecutive ADC samples
//                 - status register shows data available
//                 - if the downstream stream is not ready, the loss must be flagged
//                   (control register readback bit 31, sticky until the next record starts;
//                   the status register can't be used: software takes bits 29:0 as the count)
//                 - AXI-Lite protocol checked (RDATA stable under back-pressure)
//////////////////////////////////////////////////////////////////////////////////

module tb_wideband_collect;

  reg aclk = 0;
  reg aresetn = 0;
  always #4 aclk = ~aclk;

`include "axil_tb_bus.vh"

  wire [63:0] m_tdata;
  wire        m_tvalid;
  reg         m_tready = 1;
  wire        startrecord;
  reg  [31:0] fifo_count = 0;
  reg  [15:0] adc0 = 0, adc1 = 16'h8000;
  always @(posedge aclk) begin adc0 <= adc0 + 1; adc1 <= adc1 + 1; end

  Wideband_Collect dut (.aclk(aclk), .aresetn(aresetn), `AXIL_SLAVE_PORTS,
    .m_axis_tdata(m_tdata), .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready),
    .startrecord(startrecord), .fifo_count(fifo_count), .adc0(adc0), .adc1(adc1));

  integer errors = 0;
  reg ok;
  reg [31:0] d;
`include "tb_helpers.vh"

  // sink: count words and check each holds 4 consecutive samples
  integer words = 0;
  always @(posedge aclk)
    if(m_tvalid && m_tready)
    begin
      words = words + 1;
      fifo_count <= fifo_count + 1;
      if(m_tdata[31:16] !== m_tdata[15:0] + 16'd1 || m_tdata[47:32] !== m_tdata[15:0] + 16'd2 ||
         m_tdata[63:48] !== m_tdata[15:0] + 16'd3)
      begin
        $display("%0t ERROR: non consecutive samples 0x%0h", $time, m_tdata);
        errors = errors + 1;
      end
    end

  task wait_available;
    input integer bit_n;
    integer t;
    begin
      t = 0; d = 0;
      while(!d[bit_n] && t < 2000) begin bfm.read(16'h000C, d, ok); t = t + 1; end
      check_true("data available", d[bit_n]);
    end
  endtask

  initial
  begin
    repeat(5) @(posedge aclk);
    aresetn = 1;
    repeat(5) @(posedge aclk);

    // 1. record 16 words of ADC0, sink always ready
    bfm.write(16'h0004, 32'd2000, ok);         // record period
    bfm.write(16'h0008, 32'd15, ok);           // depth-1
    bfm.write(16'h0000, 32'h1, ok);            // enable ADC0
    wait_available(30);
    check_eq("words recorded", words, 16);
    bfm.read(16'h0000, d, ok);
    check_eq("no loss flagged", d[31], 0);
    check_eq("control readback", d[2:0], 3'b001);
    bfm.rready_delay = 4;
    bfm.read(16'h000C, d, ok);                 // status with back-pressure (fifo_count may move)
    bfm.rready_delay = 0;

    // 2. acknowledge, then next record with downstream stalled part of the time
    words = 0;
    fork
      begin
        wait(startrecord);
        repeat(20) @(posedge aclk);
        m_tready = 0;
        repeat(12) @(posedge aclk);
        m_tready = 1;
      end
      bfm.write(16'h0000, 32'h5, ok);          // data read out, keep ADC0 enabled
    join
    wait_available(30);
    check_true("fewer than 16 words delivered while stalled", words < 16);
    check_eq("status count bits unaffected", d[29:14], 0);
    bfm.read(16'h0000, d, ok);
    check_eq("loss flagged in control bit 31", d[31], 1);

    // 3. next clean record clears the flag
    words = 0;
    bfm.write(16'h0000, 32'h5, ok);
    repeat(50) @(posedge aclk);
    wait_available(30);
    check_eq("words recorded (3)", words, 16);
    bfm.read(16'h0000, d, ok);
    check_eq("loss flag cleared by new record", d[31], 0);

    finish_test(bfm.error_count + chk.error_count);
  end

  initial begin #5_000_000; $display("ERROR: global timeout"); $display("TEST FAIL"); $finish; end
endmodule
