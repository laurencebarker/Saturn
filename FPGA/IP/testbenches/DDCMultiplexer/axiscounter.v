//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR 
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    11.10.2022 
// Design Name:    axiscounter.v
// Module Name:    AXIS_Counter
// Project Name:   Saturn 
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    Module to generate a counting data sequence on an AXI data stream, for test
// generates a new count value on each transaction as the bottom 16 bits oou
// the top 32 bits come from the parameter

// 
// I/O signals:
//          aclk                master clock
//          aresetn             active low asynchronous reset signal
//          M00axisxxxx         output axi stream
//
// Dependencies: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: 
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1 ns / 1 ps


module AXIS_Test_Counter #
(
  parameter Topbits = 000000          // top32 bits
)
(
  // System signals
  input wire                        aclk,
  input wire                        aresetn,
  // AXI stream master outputs
  output reg [47:0]                 m_axis_tdata,        // output stream
  output reg                        m_axis_tvalid,
  input wire                        m_axis_tready 
);


//
// internal registers
//
  reg [15:0] counter;                          // internal count          


//
//
//
    always @(posedge aclk)
    begin
        if (~aresetn)                   // reset processing
        begin
            m_axis_tvalid <= 0;
            m_axis_tdata <= 0;
            counter <= 0;
        end
        
        else                            // normal processing
        begin
            m_axis_tvalid <= 1;         // always offer data
            m_axis_tdata[47:16] <= Topbits;
            m_axis_tdata[15:0] <= counter;
            if ((m_axis_tvalid ==1) && (m_axis_tready==1))
                counter <= counter + 1;
        end
    end

endmodule