`timescale 1ns / 1ps
// SOURCES: axis_adder.v
//////////////////////////////////////////////////////////////////////////////////
// Module Name:    tb_axis_adder
// Description:    self checking test of axis_adder, 16 bit signed (as used in audio_codec)
//                 sum saturates at +32767 / -32768 instead of wrapping
//////////////////////////////////////////////////////////////////////////////////

module tb_axis_adder;

  reg aclk = 0;
  always #4 aclk = ~aclk;

  reg  signed [15:0] a = 0, b = 0;
  wire signed [15:0] m;
  wire ar, br, mv;
  axis_adder #(.AXIS_TDATA_WIDTH(16), .AXIS_TDATA_SIGNED("TRUE")) dut (.aclk(aclk),
    .s_axis_a_tready(ar), .s_axis_a_tdata(a), .s_axis_a_tvalid(1'b1),
    .s_axis_b_tready(br), .s_axis_b_tdata(b), .s_axis_b_tvalid(1'b1),
    .m_axis_tready(1'b1), .m_axis_tdata(m), .m_axis_tvalid(mv));

  integer errors = 0;
`include "tb_helpers.vh"

  task add_check;
    input signed [15:0] x, y;
    input signed [15:0] e;
    begin
      a = x; b = y; #1;
      if(m !== e) begin $display("ERROR: %0d + %0d = %0d expected %0d", x, y, m, e); errors = errors + 1; end
    end
  endtask

  initial
  begin
    add_check(100, -50, 50);
    add_check(16'sd30000, 16'sd10000, 16'sd32767);
    add_check(-16'sd30000, -16'sd10000, -16'sd32768);
    add_check(16'sd32767, 16'sd1, 16'sd32767);
    add_check(-16'sd32768, -16'sd1, -16'sd32768);
    add_check(16'sd32767, -16'sd32768, -16'sd1);
    finish_test(0);
  end
endmodule
