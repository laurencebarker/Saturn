`timescale 1ns / 1ps
// SOURCES: activitywatchdog.v
//////////////////////////////////////////////////////////////////////////////////
// Module Name:    tb_watchdog
// Description:    TX safety test of the FIFO activity watchdog
//                 - TX disabled from power-up and after reset
//                 - enabled while either activity input pulses
//                 - disabled TimeoutClocks after the last activity
//////////////////////////////////////////////////////////////////////////////////

module tb_watchdog;

  reg aclk = 0;
  reg aresetn = 0;
  always #4 aclk = ~aclk;

  reg a1 = 0, a2 = 0;
  wire TXEnable;
  Watchdog #(.TimeoutClocks(100)) dut (.aclk(aclk), .aresetn(aresetn), .activity1(a1), .activity2(a2),
                                       .TXEnable(TXEnable));

  integer errors = 0;
`include "tb_helpers.vh"

  integer i, t;
  initial
  begin
    #1 check_eq("TX disabled at power-up", TXEnable, 0);
    repeat(5) @(posedge aclk);
    check_eq("TX disabled in reset", TXEnable, 0);
    aresetn = 1;
    repeat(5) @(posedge aclk);
    check_eq("TX disabled without activity", TXEnable, 0);

    for(i = 0; i < 20; i = i + 1)             // activity every 50 clocks, alternating inputs
    begin
      #1 if(i[0]) a1 = 1; else a2 = 1;
      @(posedge aclk); #1 a1 = 0; a2 = 0;
      repeat(49) @(posedge aclk);
      if(TXEnable !== 1'b1) begin $display("ERROR: TX dropped during activity"); errors = errors + 1; end
    end
    t = 0;
    while(TXEnable && t < 1000) begin @(posedge aclk); t = t + 1; end
    check_true("TX disabled ~100 clocks after last activity", (t >= 45) && (t <= 55));
    repeat(200) @(posedge aclk);
    check_eq("TX stays disabled", TXEnable, 0);
    finish_test(0);
  end
endmodule
