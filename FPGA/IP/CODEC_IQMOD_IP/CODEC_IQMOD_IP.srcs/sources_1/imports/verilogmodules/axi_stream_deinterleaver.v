//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    16.08.2021
// Design Name:    axi_stream_deinterleaver.v
// Module Name:    AXIS_Ddinterleaver
// Project Name:   Saturn 
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    Module to propagate an axi stream to 1 or 2 destinations.
// This is to pass I/Q TX samples to the DUC, or interleaved samples to DUC & envelope gen. 
// if not enabled: pass no data, and ne ready to restart on "even" sample
// if enabled, not deinterleaved: passes data to o/p stream 0
// if enabled and deinterleaved: alternate samples go to o/p streams 0 & 1
// to change over:
// set enabled = 0; change deinterleaved bit; set enabled = 1
//
// deinteleave=0:
// S00-> M00
// S00-> M00
//
// deinterleave=1, oddbeat=0:         deinterleave=1, oddbeat=1:
// S00 -> M00                         S00 -> M01
//

// 
// I/O signals:
//          aclk                master clock
//          aresetn             asynchronous reset signal
//          deinterleave        true if to deinterleave 
//          enabled             true if interface enabled; if false doesn't transfer 
//
// Dependencies: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: 
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1 ns / 1 ps


module AXIS_Deinterleaver #
(
  parameter AXIS_SIZE = 48          // input bus width
)
(
  // System signals
  input wire                       aclk,
  input wire                       aresetn,
  input wire                       deinterleave,    // 1 if deinterleave; 0 if propagate
  input wire                       enabled,

  // AXI stream Slave inputs
  input wire [AXIS_SIZE-1:0]       s_axis_tdata,      // input stream
  input wire                       s_axis_tvalid,
  output wire                      s_axis_tready, 

  // AXI stream master outputs
  output wire [AXIS_SIZE-1:0]      m00_axis_tdata,      // output A stream
  output wire                      m00_axis_tvalid,
  input wire                       m00_axis_tready, 

  output wire [AXIS_SIZE-1:0]      m01_axis_tdata,      // output B stream
  output wire                      m01_axis_tvalid,
  input wire                       m01_axis_tready 
);
//
// internal registers
//
  reg oddbeat = 0;                              // alternate even/odd. Steam 0 if oddbeat=0;
//
// axi stream input registers
//
  reg [AXIS_SIZE-1:0] s_axis_tdata_reg;
  reg s_axis_tready_reg;
  reg int_axis_tvalid_reg;                // tvalid from stage 1 to stage 2

//
// axi stream output registers
//
  reg [AXIS_SIZE-1:0] m00_axis_tdata_reg;
  reg [AXIS_SIZE-1:0] m01_axis_tdata_reg;
  reg m00_axis_tvalid_reg;
  reg m01_axis_tvalid_reg;
  reg int_axis_tready_reg;                // tready from stage 2 to stage 1

  assign s_axis_tready = s_axis_tready_reg;
  assign m00_axis_tdata = m00_axis_tdata_reg;
  assign m01_axis_tdata = m01_axis_tdata_reg;
  assign m00_axis_tvalid = m00_axis_tvalid_reg;
  assign m01_axis_tvalid = m01_axis_tvalid_reg;


//
// logic for the axi stream input buffers
// Coded lazily and therefore simply:
// the stage can accept an input transfer in one cycle and output transfer in the next
// but not one data beat per clock cycle.
//
  always @(posedge aclk)
  begin
    if(~aresetn | ~enabled)
    begin
// reset to start states. Deassert axi master and slave strobes; clear data registers
      s_axis_tready_reg <= 1;                         // ready to accept transfers
      s_axis_tdata_reg <= 0;
      int_axis_tvalid_reg <= 0;                       // no data held at reset
    end
    else		//!aresetn
    begin
      if(s_axis_tvalid & s_axis_tready_reg)           // complete a slave read
      begin
        s_axis_tdata_reg <= s_axis_tdata;             // latch the data
        s_axis_tready_reg <= 0;                       // can't accept until consumed
        int_axis_tvalid_reg <= 1;                     // data available
      end
      if(int_axis_tvalid_reg & int_axis_tready_reg)   // complete a master write
      begin
        int_axis_tvalid_reg <= 0;
        s_axis_tready_reg <= 1;                       // can accept new data
      end
    end         // if(!aresetn)
  end           // always @


//
// logic for the axi stream output buffers
// more complex. treat in two halves: operating when non multiplexed, and operating when multiplexed
//
  always @(posedge aclk)
  begin
    if(~aresetn)
    begin
// reset to start states. Deassert axi master and slave strobes; clear data registers
      m00_axis_tvalid_reg <= 0;
      m01_axis_tvalid_reg <= 0;
      m00_axis_tdata_reg <= 0;
      m01_axis_tdata_reg <= 0;
      int_axis_tready_reg <= 1;                 // tready from stage 2 to stage 1
      oddbeat <= 0;                             // point to stream 0 
    end
    
    else if(oddbeat==0)		                    // data goes to stream 0
    begin
// stream 0
      if(int_axis_tvalid_reg & int_axis_tready_reg)     // accept data if available & ready
      begin
        m00_axis_tdata_reg <= s_axis_tdata_reg;         // latch the data
        int_axis_tready_reg <= 0;                       // can't accept until consumed
        m00_axis_tvalid_reg <= 1;                       // data available
      end
      if(m00_axis_tvalid_reg & m00_axis_tready)         // complete a master write
      begin
        m00_axis_tvalid_reg <= 0;
        int_axis_tready_reg <= 1;                       // can accept new data
        if(deinterleave)
          oddbeat <= ~oddbeat;                          // advance oddbeat if needed
      end
    end
    else                                                    // odd data beat
    begin
// stream 1
      if(int_axis_tvalid_reg & int_axis_tready_reg)     // accept data if available & ready
      begin
        m01_axis_tdata_reg <= s_axis_tdata_reg;         // latch the data
        int_axis_tready_reg <= 0;                       // can't accept until consumed
        m01_axis_tvalid_reg <= 1;                       // data available
      end
      if(m01_axis_tvalid_reg & m01_axis_tready)         // complete a master write
      begin
        m01_axis_tvalid_reg <= 0;
        int_axis_tready_reg <= 1;                       // can accept new data
        if(deinterleave)
          oddbeat <= ~oddbeat;                          // advance oddbeat if needed
      end
    end         // odd data beat
  end           // always @

endmodule