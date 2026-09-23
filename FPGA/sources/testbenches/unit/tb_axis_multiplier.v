`timescale 1ns / 1ps
// SOURCES: axis_multiplier.v
//////////////////////////////////////////////////////////////////////////////////
// Module Name:    tb_axis_multiplier
// Description:    self checking test of axis_multiplier (16x16 -> 16, Q15 style)
//                 result = saturate(round_nearest(a*b / 2^15))
//                 - random values and corner cases including (-32768)*(-32768)
//                 - stream handshakes with output back-pressure
//////////////////////////////////////////////////////////////////////////////////

module tb_axis_multiplier;

  reg aclk = 0;
  reg aresetn = 0;
  always #4 aclk = ~aclk;

  reg  signed [15:0] a = 0, b = 0;
  reg  av = 0, bv = 0;
  wire ar, br;
  wire signed [15:0] m;
  wire mv;
  reg  mr = 1;

  axis_multiplier #(.S00Size(16), .S01Size(16), .MSize(16)) dut (.aclk(aclk), .aresetn(aresetn),
    .s00_axis_tdata(a), .s00_axis_tvalid(av), .s00_axis_tready(ar),
    .s01_axis_tdata(b), .s01_axis_tvalid(bv), .s01_axis_tready(br),
    .m_axis_tdata(m), .m_axis_tvalid(mv), .m_axis_tready(mr));

  axis_checker #(.DATA_WIDTH(16), .NAME("m_axis")) chk (.aclk(aclk), .aresetn(aresetn),
    .tdata(m), .tvalid(mv), .tready(mr));

  integer errors = 0;
`include "tb_helpers.vh"

  function signed [15:0] ref_mult;
    input signed [15:0] x, y;
    reg signed [40:0] p;
    begin
      p = x * y;
      p = (p + 41'sd16384) >>> 15;
      if(p > 32767) p = 32767;
      if(p < -32768) p = -32768;
      ref_mult = p[15:0];
    end
  endfunction

  reg signed [15:0] exp [0:1023];
  integer wr = 0, rd = 0;
  always @(posedge aclk)
  begin
    mr <= $random;
    if(mv && mr)
    begin
      if(m !== exp[rd]) begin if(errors < 10) $display("%0t ERROR: result %0d expected %0d", $time, m, exp[rd]); errors = errors + 1; end
      rd = rd + 1;
    end
  end

  task mult;
    input signed [15:0] x, y;
    begin
      exp[wr] = ref_mult(x, y); wr = wr + 1;
      #1 a = x; b = y; av = 1; bv = 1;
      @(posedge aclk);
      while(!(ar && br)) @(posedge aclk);
      #1 av = 0; bv = 0;
    end
  endtask

  integer i;
  initial
  begin
    repeat(5) @(posedge aclk);
    aresetn = 1;
    mult(-16'sd32768, -16'sd32768);
    mult(16'sd32767, 16'sd32767);
    mult(-16'sd32768, 16'sd32767);
    mult(16'sd1, 16'sd16384);
    mult(-16'sd1, 16'sd16384);
    mult(16'sd0, -16'sd32768);
    for(i = 0; i < 500; i = i + 1) mult($random, $random);
    repeat(100) @(posedge aclk);
    check_eq("all results delivered", rd, wr);
    finish_test(chk.error_count);
  end
endmodule
