//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    15/2/2025 19:30
// Design Name:    activitywatchdog.v
// Module Name:    Watchdog
// Project Name:   Saturn 
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    Module to monitor activity on main FIFO reads and writes
//                 and assert TX enable only when FIFOs are being accessed
//                 this is a protection against software crast during TX
//
// 
// I/O signals:
//          aclk                master clock
//          aresetn             asynchronous reset signal
//          activity1           if 1, a data transfer has occurred in a FIFO reader/writer
//          activity2           if 1, a data transfer has occurred in a FIFO reader/writer
//          TXEnable            if 1, TX is allowed
//
//
// Dependencies: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: 
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1 ns / 1 ps


module Watchdog #
(
  parameter integer TimeoutClocks = 1000        // no. clocks before timeout declared
)

(
  // System signals
  input wire             aclk,
  input wire             aresetn,
  input wire             activity1,
  input wire             activity2,

  output reg             TXEnable
);
//
// internal registers
//
  reg [31:0]counter = 2'b00;                  // sequencer for control  
//
  always @(posedge aclk)
  begin
    if(~aresetn)
    begin
// reset to start states. Deassert axi master and slave strobes; clear data registers
      counter <= 0;
      TXEnable <= 0;
    end
    else		//!aresetn
    begin
      if(activity1 || activity2)
      begin
        counter <= TimeoutClocks;
        TXEnable <= 1;
      end
      else if (counter != 0)
      begin
        counter <= counter - 1;
        TXEnable <= 1;
      end
      else
        TXEnable <= 0;
    end
  end         // if(!aresetn)
endmodule