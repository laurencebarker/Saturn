`timescale 1ns / 1ps
// SOURCES: PTTATUGate.v
//////////////////////////////////////////////////////////////////////////////////
// Module Name:    tb_ptt_atu_gate
// Description:    self checking test of PTTATUGate
//                 - PTT passes through when no ATU request
//                 - PTT never asserted (not even for one clock) while an ATU request is
//                   active, including when PTT and ATU request assert together
//                 - after ATU tune, PTT stays off until PTT is released
//////////////////////////////////////////////////////////////////////////////////

module tb_ptt_atu_gate;

  reg aclk = 0;
  reg aresetn = 0;
  always #4 aclk = ~aclk;

  reg PTTIn = 0, ATURequest = 0;
  wire PTTOut;
  PTTATUGate dut (.PTTIn(PTTIn), .ATURequest(ATURequest), .aclk(aclk), .PTTOut(PTTOut), .aresetn(aresetn));

  integer errors = 0;
`include "tb_helpers.vh"

  reg watch = 0;
  integer glitches = 0;
  always @(posedge aclk) if(watch && PTTOut) glitches = glitches + 1;

  initial
  begin
    repeat(5) @(posedge aclk);
    aresetn = 1;
    repeat(5) @(posedge aclk);

    #1 PTTIn = 1; repeat(5) @(posedge aclk);
    check_eq("PTT passes", PTTOut, 1);
    #1 PTTIn = 0; repeat(5) @(posedge aclk);
    check_eq("PTT released", PTTOut, 0);

    // ATU request and PTT together
    watch = 1;
    #1 PTTIn = 1; ATURequest = 1;
    repeat(20) @(posedge aclk);
    #1 ATURequest = 0;                        // tune finished, PTT still held
    repeat(20) @(posedge aclk);
    check_eq("no PTT out during or after ATU tune", glitches, 0);
    watch = 0;
    #1 PTTIn = 0; repeat(5) @(posedge aclk);
    #1 PTTIn = 1; repeat(5) @(posedge aclk);
    check_eq("PTT works again after release", PTTOut, 1);

    // ATU request while transmitting drops PTT
    #1 ATURequest = 1; repeat(3) @(posedge aclk);
    check_eq("ATU request drops PTT", PTTOut, 0);
    #1 ATURequest = 0; PTTIn = 0;

    finish_test(0);
  end
endmodule
