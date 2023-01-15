//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    25/10/2022 17:18:01
// Design Name:    byteswap_48bit.v
// Module Name:    byteswap_48
// Project Name:   Saturn 
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    Module to swap bytes for a 48 bit DDC or DUC I/Q word
// This operates on a single I/Q word. 
// If swap not selected, I/Q data will be transferred "as is" which
// will be correctly ordered for Raspberry pi local processing.
// if swap selected, I and Q data will be transferred in byteswapped
// form which will be network byte order.
// 
// 
// I/O signals:
//          aclk                master clock
//          swap                true if swapping selected 
//          Saxisxxxx           input axi stream
//          Maxisxxxx           output axi stream
//
// Dependencies: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: 
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1 ns / 1 ps
module byteswap_48
(
  // System signals
  input wire                        aclk,
  input wire                        aresetn,
  input wire                        swap,           // swap control
  input wire [47:0]                 s_axis_tdata,
  input wire                        s_axis_tvalid,
  output wire                       s_axis_tready,

  // Master side
  output reg [47:0]                m_axis_tdata,
  output reg                       m_axis_tvalid,
  input wire                        m_axis_tready
);

    assign s_axis_tready = aresetn ? !m_axis_tvalid : 0;          // ready for new data if none held locally

    always @(posedge aclk)
    begin
        if(!aresetn)
        begin
            m_axis_tdata <= 0;
            m_axis_tvalid <= 0;
        end
        else
        begin 
            if(s_axis_tready && s_axis_tvalid)              // if input transaction completes
            begin
                m_axis_tvalid <= 1; 
                m_axis_tdata <= swap ? {s_axis_tdata[31:24], s_axis_tdata[39:32], s_axis_tdata[47:40], s_axis_tdata[7:0], s_axis_tdata[15:8], s_axis_tdata[23:16]}:s_axis_tdata;
            end
            
            if(m_axis_tready && m_axis_tvalid)              // if output transaction completes
                m_axis_tvalid <= 0;                         // and this causes a new input transaction to begin
        end
    end
endmodule

