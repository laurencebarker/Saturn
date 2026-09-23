`timescale 1ns / 1ps
// SOURCES: clock-monitor.v
//////////////////////////////////////////////////////////////////////////////////
// Module Name:    tb_clock_monitor
// Description:    self checking test of clock_monitor
//                 - dout bits set while each monitored clock runs, cleared when it stops
//                 - dout defined from reset; LED blinks only when all 4 clocks run
//////////////////////////////////////////////////////////////////////////////////

module tb_clock_monitor;

  reg aclk = 0;
  reg aresetn = 0;
  always #4 aclk = ~aclk;

  reg ck0 = 0, ck1 = 0, ck2 = 0, ck3 = 0;
  reg [3:0] run = 4'b1111;
  always #13 if(run[0]) ck0 = ~ck0;
  always #50 if(run[1]) ck1 = ~ck1;
  always #7  if(run[2]) ck2 = ~ck2;
  always #21 if(run[3]) ck3 = ~ck3;

  wire [3:0] dout;
  wire LED;
  clock_monitor #(.MONOSTABLE_TICKS(100), .BLINK_HALFPERIOD(500)) dut (.aclk(aclk), .aresetn(aresetn),
    .ck0(ck0), .ck1(ck1), .ck2(ck2), .ck3(ck3), .dout(dout), .LED(LED));

  integer errors = 0;
`include "tb_helpers.vh"

  integer toggles = 0;
  reg prev_led = 0;
  always @(posedge aclk) begin if(LED !== prev_led) toggles = toggles + 1; prev_led = LED; end

  initial
  begin
    repeat(3) @(posedge aclk);
    check_eq("dout reset value", dout, 4'b0000);
    aresetn = 1;
    repeat(3000) @(posedge aclk);
    check_eq("all clocks running", dout, 4'b1111);
    check_true("LED blinking", toggles >= 4);
    run[2] = 0;
    repeat(300) @(posedge aclk);
    check_eq("clock 2 stopped", dout, 4'b1011);
    toggles = 0;
    repeat(2000) @(posedge aclk);
    check_eq("LED off when a clock stopped", toggles, 0);
    finish_test(0);
  end
endmodule
