`timescale 1 ns / 1 ps

//////////////////////////////////////////////////////////////////////////////////
// Engineer: Laurence Barker G8NJJ 
// 
// Create Date: 05.01.2023 // Design Name: 
// Module Name: HalfLSBIQAdder
// Target Devices: Artix 7
// Tool Versions: Vivado 2021.1
// Description: adds a half LSB to input word, and makes word 1 bit wider 
// 
// Dependencies: none 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module HalfLSBIQAdder
(
  // System signals
  input wire aclk,
  input  wire [31:0] s_axis_tdata,
  input  wire s_axis_tvalid,
  output wire s_axis_tready,
   
  output wire [47:0] m_axis_tdata,
  output wire m_axis_tvalid,
  input wire m_axis_tready
);

  wire TopI;
  wire TopQ;
  
  assign TopI = s_axis_tdata[15];
  assign TopQ = s_axis_tdata[31];
  
  assign s_axis_tready = m_axis_tready;
  assign m_axis_tvalid = s_axis_tvalid;
  assign m_axis_tdata[47] = TopQ;
  assign m_axis_tdata[46] = TopQ;
  assign m_axis_tdata[45] = TopQ;
  assign m_axis_tdata[44] = TopQ;
  assign m_axis_tdata[43] = TopQ;
  assign m_axis_tdata[42] = TopQ;
  assign m_axis_tdata[41] = TopQ;
  assign m_axis_tdata[40:25] = s_axis_tdata[31:16];
  assign m_axis_tdata[24] = 1;

  assign m_axis_tdata[23] = TopI;
  assign m_axis_tdata[22] = TopI;
  assign m_axis_tdata[21] = TopI;
  assign m_axis_tdata[20] = TopI;
  assign m_axis_tdata[19] = TopI;
  assign m_axis_tdata[18] = TopI;
  assign m_axis_tdata[17] = TopI;
  assign m_axis_tdata[16:1] = s_axis_tdata[15:0];
  assign m_axis_tdata[0] = 1;
  

endmodule