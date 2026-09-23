`timescale 1ns / 1ps
// SOURCES: axi_stream_deinterleaver.v
//////////////////////////////////////////////////////////////////////////////////
// Module Name:    tb_axis_deinterleaver
// Description:    self checking test of AXIS_Deinterleaver (TX I/Q / EER splitter)
//                 - deinterleave=0: all samples to m00, in order
//                 - deinterleave=1: even samples to m00, odd to m01
//                 - documented changeover (enabled=0, change mode, enabled=1) after an
//                   odd number of samples must restart on m00
//                 - random back-pressure on both outputs; protocol checked
//////////////////////////////////////////////////////////////////////////////////

module tb_axis_deinterleaver;

  reg aclk = 0;
  reg aresetn = 0;
  always #4 aclk = ~aclk;

  reg         deinterleave = 0, enabled = 0;
  reg  [47:0] s_tdata = 0;
  reg         s_tvalid = 0;
  wire        s_tready;
  wire [47:0] m00_tdata, m01_tdata;
  wire        m00_tvalid, m01_tvalid;
  reg         m00_tready = 1, m01_tready = 1;
  reg         random_ready = 0;

  AXIS_Deinterleaver #(.AXIS_SIZE(48)) dut (
    .aclk(aclk), .aresetn(aresetn), .deinterleave(deinterleave), .enabled(enabled),
    .s_axis_tdata(s_tdata), .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready),
    .m00_axis_tdata(m00_tdata), .m00_axis_tvalid(m00_tvalid), .m00_axis_tready(m00_tready),
    .m01_axis_tdata(m01_tdata), .m01_axis_tvalid(m01_tvalid), .m01_axis_tready(m01_tready));

  axis_checker #(.DATA_WIDTH(48), .NAME("m00")) chk0 (.aclk(aclk), .aresetn(aresetn),
    .tdata(m00_tdata), .tvalid(m00_tvalid), .tready(m00_tready));
  axis_checker #(.DATA_WIDTH(48), .NAME("m01")) chk1 (.aclk(aclk), .aresetn(aresetn),
    .tdata(m01_tdata), .tvalid(m01_tvalid), .tready(m01_tready));

  integer errors = 0;
`include "tb_helpers.vh"

  // scoreboards: expected data per output
  reg [47:0] exp0 [0:1023];
  reg [47:0] exp1 [0:1023];
  integer wr0 = 0, rd0 = 0, wr1 = 0, rd1 = 0;

  always @(posedge aclk)
  begin
    if(random_ready) begin m00_tready <= $random; m01_tready <= $random; end
    if(m00_tvalid && m00_tready)
    begin
      if(rd0 >= wr0) begin $display("%0t ERROR: unexpected m00 data 0x%0h", $time, m00_tdata); errors = errors + 1; end
      else begin
        if(m00_tdata !== exp0[rd0]) begin $display("%0t ERROR: m00 got 0x%0h exp 0x%0h", $time, m00_tdata, exp0[rd0]); errors = errors + 1; end
        rd0 = rd0 + 1;
      end
    end
    if(m01_tvalid && m01_tready)
    begin
      if(rd1 >= wr1) begin $display("%0t ERROR: unexpected m01 data 0x%0h", $time, m01_tdata); errors = errors + 1; end
      else begin
        if(m01_tdata !== exp1[rd1]) begin $display("%0t ERROR: m01 got 0x%0h exp 0x%0h", $time, m01_tdata, exp1[rd1]); errors = errors + 1; end
        rd1 = rd1 + 1;
      end
    end
  end

  task send;
    input [47:0] d;
    input        to1;          // expected output
    integer t;
    begin
      if(to1) begin exp1[wr1] = d; wr1 = wr1 + 1; end
      else    begin exp0[wr0] = d; wr0 = wr0 + 1; end
      #1 s_tdata = d; s_tvalid = 1; t = 0;
      @(posedge aclk);
      while(!s_tready && t < 1000) begin @(posedge aclk); t = t + 1; end
      #1 s_tvalid = 0;
      if(t >= 1000) begin $display("ERROR: input stalled"); errors = errors + 1; end
    end
  endtask

  task drain;
    integer t;
    begin
      t = 0;
      while((rd0 < wr0 || rd1 < wr1) && t < 2000) begin @(posedge aclk); t = t + 1; end
      check_eq("m00 all delivered", rd0, wr0);
      check_eq("m01 all delivered", rd1, wr1);
    end
  endtask

  integer i;
  initial
  begin
    repeat(5) @(posedge aclk);
    aresetn = 1;
    @(posedge aclk);

    // 1. pass through
    enabled = 1; deinterleave = 0;
    for(i = 0; i < 8; i = i + 1) send(48'h100 + i, 0);
    drain;

    // 2. deinterleave with random back-pressure
    enabled = 0; @(posedge aclk); deinterleave = 1; @(posedge aclk); enabled = 1;
    random_ready = 1;
    for(i = 0; i < 64; i = i + 1) send(48'h200 + i, i[0]);
    drain;

    // 3. odd number of samples, then documented changeover to pass-through
    for(i = 0; i < 3; i = i + 1) send(48'h300 + i, i[0]);
    drain;
    enabled = 0; @(posedge aclk); deinterleave = 0; @(posedge aclk); enabled = 1;
    for(i = 0; i < 8; i = i + 1) send(48'h400 + i, 0);
    drain;

    // 4. and back to deinterleave: must restart on m00
    enabled = 0; @(posedge aclk); deinterleave = 1; @(posedge aclk); enabled = 1;
    for(i = 0; i < 8; i = i + 1) send(48'h500 + i, i[0]);
    drain;

    finish_test(chk0.error_count + chk1.error_count);
  end

  initial begin #2_000_000; $display("ERROR: global timeout"); $display("TEST FAIL"); $finish; end
endmodule
