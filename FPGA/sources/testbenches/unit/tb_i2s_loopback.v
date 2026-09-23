`timescale 1ns / 1ps
// SOURCES: i2s_clk_lrclk_gen.v I2S_xmit.v I2S_rcv.v
//////////////////////////////////////////////////////////////////////////////////
// Module Name:    tb_i2s_loopback
// Description:    I2S clock generator + transmitter looped back into the receiver.
//                 every stereo word sent must be received, unchanged and in order,
//                 including when the receiver output is read with TREADY asserted in the
//                 same cycle a new word arrives (TREADY held high).
//////////////////////////////////////////////////////////////////////////////////

module tb_i2s_loopback;

  reg aclk = 0;                              // 12.288 MHz
  always #40.69 aclk = ~aclk;
  reg resetn = 0;

  wire BCLK, Brise, Bfall, LRCLK, LRrise, LRfall;
  i2s_clk_lrclk_gen clkgen (.resetn(resetn), .CLK_IN(aclk), .BCLK(BCLK), .Brise(Brise), .Bfall(Bfall),
    .LRCLK(LRCLK), .LRrise(LRrise), .LRfall(LRfall));

  reg  [31:0] tx_data = 32'h1234_8001;
  wire        tx_ready;
  wire        sdata;
  I2S_xmit xmit (.resetn(resetn), .aclk(aclk), .lrclk(LRCLK), .CBrise(Brise), .CBfall(Bfall), .outbit(sdata),
    .sxmit_axis_tdata(tx_data), .sxmit_axis_tready(tx_ready), .sxmit_axis_tvalid(1'b1));

  wire [31:0] rx_data;
  wire        rx_valid;
  I2S_rcv rcv (.resetn(resetn), .aclk(aclk), .Brise(Brise), .Bfall(Bfall), .LRrise(LRrise), .LRfall(LRfall),
    .mrecv_axis_tdata(rx_data), .mrecv_axis_tvalid(rx_valid), .mrecv_axis_tready(1'b1),
    .BCLK(BCLK), .LRCLK(LRCLK), .din(sdata));

  integer errors = 0;
`include "tb_helpers.vh"

  // transmitted words: tx_data advances after each handshake
  reg [31:0] sent [0:255];
  integer ns = 0, nr = 0, first = -1;
  always @(posedge aclk)
    if(resetn && tx_ready)
    begin
      sent[ns] = tx_data; ns = ns + 1;
      tx_data <= tx_data + 32'h0101_0101;
    end
  always @(posedge aclk)
    if(rx_valid)
    begin
      if(first < 0)                         // find the sent word matching the first received
        begin : find
          integer k;
          for(k = 0; k < ns; k = k + 1) if(sent[k] === rx_data) first = k;
          if(first < 0) begin $display("ERROR: first received word 0x%0h never sent", rx_data); errors = errors + 1; first = 0; end
          nr = first;
        end
      if(rx_data !== sent[nr]) begin if(errors < 10) $display("%0t ERROR: received 0x%0h expected 0x%0h", $time, rx_data, sent[nr]); errors = errors + 1; end
      nr = nr + 1;
    end

  initial
  begin
    repeat(10) @(posedge aclk);
    resetn = 1;
    repeat(256*30) @(posedge aclk);         // ~30 stereo frames
    check_true("words received", (nr - first) >= 20);
    check_true("no words lost (received = sent - pipeline)", (ns - nr) <= 3);
    finish_test(0);
  end
endmodule
