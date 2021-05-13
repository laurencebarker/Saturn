
//
//  HPSDR - High Performance Software Defined Radio
//
//  Hermes code. 
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

// (C) Kirk Weedman KD7IRS  2006, 2007, 2008, 2009, 2010, 2011, 2012 




// By Kirk Weedman KD7IRS - Feb 27 2009
// 
// Implements I2S transmit, DATA_BITS of data per channel, two channels 
// 
// 
// In I2S mode the MSB of the left sample is available on the second rising edge of BCLK
// following a falling  edge on lrclk.  Simiarily the MSB of the right sample will be available on 
// the second rising edge of BCLK following the rising edge of lrclk.

// NOTE: the data to send is latched on the positive edge of lrclk
//
// modified Laurence Barker G8NJJ to configure for axi 4 stream interface 
//
`timescale 1ns/100ps

module I2S_xmit (resetn, aclk, lrclk, CBrise, CBfall, outbit, sxmit_axis_tdata, sxmit_axis_tready, sxmit_axis_tvalid);

parameter DATA_BITS = 32; // MUST be an even number
parameter TPD = 5;

localparam NB = DATA_BITS/2;       // size of left or right data
localparam NS = clogb2(NB-1);

(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK" *)
(* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET resetn" *)
input  wire          aclk;         // system clock that generates BCLK
(* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 resetn RST" *)
(* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
input  wire          resetn;
input  wire          lrclk;        // left/right clock 
input  wire          CBrise;       // CBCLK rising edge trigger 
input  wire          CBfall;       // CBCLK rising edge trigger - when to change data 
output reg           outbit;       // output bit 
input  wire [DATA_BITS-1:0] sxmit_axis_tdata;       // left & right data to be clocked out 
input  wire          sxmit_axis_tvalid;     // acknowledge handshake
output reg           sxmit_axis_tready;     // ready for more data

reg   [NB-1:0] data;               // data to be clocked out 
reg   [DATA_BITS-1:0] last_data; 
reg   [NS-1:0] bit_count;          // how many bits clocked, must prst to MSB 
reg      [2:0] TLV_state;
reg      [2:0] TLV_state_next;
reg            obit;

localparam TLV_IDLE   = 0,
           TLV_WH     = 1,
           TLV_LR_LO  = 2,
           TLV_WL     = 3,
           TLV_LR_HI  = 4;


always @(posedge aclk)
begin
  if (!resetn)
    TLV_state <= #TPD TLV_IDLE;
  else
    TLV_state <= #TPD TLV_state_next;
  // the I2S data must be available/setup before the 2nd postive edge of bclk after the clrclk goes

// assert TREADY in idle state; deassert after TVALID was true, and latch data
  if (!resetn)
  begin
    sxmit_axis_tready <= #TPD 1'b0;
    last_data <= #TPD 1'b0;
  end
  else if (TLV_state == TLV_IDLE)                   //  assert TREADY in next cycle
    sxmit_axis_tready <= #TPD 1'b1;
  else if (sxmit_axis_tready && sxmit_axis_tvalid)  // clear TREADY & latch when TVALID asserted
  begin
    sxmit_axis_tready <= #TPD 1'b0;
    last_data <= #TPD sxmit_axis_tdata;
  end
    

  if (TLV_state == TLV_WH) // load
    data <= #TPD last_data[DATA_BITS-1:NB]; // Left Data
  else if (TLV_state == TLV_WL) // load
    data <= #TPD last_data[NB-1:0]; // Right Data
  else if (CBrise)
    data <= #TPD data << 1;  // shift out MSB first

  if (CBrise)
    obit <= #TPD data[NB-1];        // copy bit 15 out

  if (CBfall)
    outbit <= #TPD obit;            // drive bit 15 to output pin

  if ((TLV_state == TLV_WH) || (TLV_state == TLV_WL))
    bit_count <= #TPD NB - 1'b1;
  else if ((bit_count != 0) && CBrise)
    bit_count <= #TPD bit_count - 1'b1;

end 

always @*
begin
  case(TLV_state)
    TLV_IDLE:
    begin
      if (!lrclk)
        TLV_state_next = TLV_IDLE;      // loop until lrclk is high
      else
        TLV_state_next = TLV_WH;
    end

    TLV_WH:
    begin
      if (lrclk)
        TLV_state_next = TLV_WH;        // loop until lrclk is low
      else      
        TLV_state_next = TLV_LR_LO;
    end

    TLV_LR_LO:
    begin
      if ((bit_count == 0) & CBrise)   // wait till full length of last bit has finished
        TLV_state_next = TLV_WL; 
      else
        TLV_state_next = TLV_LR_LO;  
    end

    TLV_WL:
    begin
      if (!lrclk)
        TLV_state_next = TLV_WL;        // loop until lrclk is high
      else
        TLV_state_next = TLV_LR_HI;
    end

    TLV_LR_HI:
    begin
      if ((bit_count == 0) & CBrise)   // wait till full length of last bit has finished
        TLV_state_next = TLV_IDLE;      // done so start again
      else
        TLV_state_next = TLV_LR_HI;
    end 
  
    default:
      TLV_state_next = TLV_IDLE;
  endcase
end

function integer clogb2;
input [31:0] depth;
begin
  for(clogb2=0; depth>0; clogb2=clogb2+1)
  depth = depth >> 1;
end
endfunction

endmodule 