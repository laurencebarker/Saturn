//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    15.07.2021 17:18:01
// Design Name:    axi_stream_interleaver.v
// Module Name:    AXIS_Interleaver
// Project Name:   Saturn 
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    Module to either propagate or interleave two axi streams 
// Registers:
// note this is true even if the axi-lite bus is wider!

// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: 
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1 ns / 1 ps

module AXIS_Interleaver#
(
  parameter integer AXIS_DATA_WIDTH = 32,
)
(
  // System signals
  input  wire                      aclk,
  input  wire                      aresetn,
  input wire                       interleave,    // 1if interleave; 0 if propagate
  // AXI stream Slave 

);
//
// internal registers
//
   

  always @(posedge aclk)
  begin
    if(~aresetn)
    begin
// reset to start states

    end
    else		//!aresetn
    begin

    end         // if(!aresetn)
  end           // always @


endmodule