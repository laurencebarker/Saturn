//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    15.07.2021 17:18:01
// Design Name:    sidetoneadder.v
// Module Name:    AXIS_sidetone_adder
// Project Name:   Saturn 
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    Module to either multiple a sidetone DDS o/p by ramp &
// sidetone volume levels, then add to L/R speaker sample streams

// written because there aren't simple adder or multipler axi stream IPs
//
// this is clocked at 12.288MHz but throttled by tready from the codec interface
// tready will call for a new sample at 48KHz rate and this must propagate back to
// the DDS and FIFO interfaces
// 
// I/O signals:
//          aclk                master clock
//          aresetn             asynchronous reset signal
//          s0_axis_xxxxx       L/R speaker sample stream
//          s1_axis_xxxxx       DDS sidetone stream
//          s2_axis_xxxxx       CW keyer amplitude ramp (signed)
//          sidetone_vol        user volume setting (signed) 
//
// Dependencies: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: 
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1 ns / 1 ps


module AXIS_sidetone_adder
(
  // System signals
  input wire                       aclk,
  input wire                       aresetn,
  input wire [7:0]                 sidetone_vol,    // 1if interleave; 0 if propagate

  // AXI stream Slave inputs
  input wire [31:0]                s00_axis_tdata,      // L/R speaker sample stream (L=MSB)
  input wire                       s00_axis_tvalid,
  output wire                      s00_axis_tready, 

  input wire [15:0]                s01_axis_tdata,      // DDS sidetone stream
  input wire                       s01_axis_tvalid,
  output wire                      s01_axis_tready, 
  
  input wire [15:0]                s02_axis_tdata,      // CW keyer ramp stream
  input wire                       s02_axis_tvalid,
  output wire                      s02_axis_tready, 

  // AXI stream master outputs
  output wire [31:0]               m_axis_tdata,      	// L/R audio samples to Codec (L=MSB)
  output wire                      m_axis_tvalid,
  input wire                       m_axis_tready 

);
//
// internal registers
//
//
// axi stream input registers
//
  reg signed [15:0] s00L_axis_tdata_reg;
  reg signed [15:0] s00R_axis_tdata_reg;
  reg signed [15:0] s01_axis_tdata_reg;
  reg signed [15:0] ramp_amplitude_reg;
  reg signed [15:0] sidetone_amplitude_reg;
  reg s00_axis_tready_reg;
  reg s01_axis_tready_reg;
  reg int00_axis_tvalid_reg;                // tvalid from stage 1 to stage 2
  reg int01_axis_tvalid_reg;                // tvalid from stage 1 to stage 2
  reg [7:0] sidetone_vol_reg;               // sidetone volume latched
  
  wire signed [15:0] scaled_sidetone_wire;

//
// axi stream output registers
//
  reg signed [15:0] mL_axis_tdata_reg;
  reg signed [15:0] mR_axis_tdata_reg;
  reg m_axis_tvalid_reg;
  reg int_axis_tready_reg;                  // tready from stage 2 to stage 1

  assign s00_axis_tready = s00_axis_tready_reg;
  assign s01_axis_tready = s01_axis_tready_reg;
  assign m00_axis_tdata[15:0] = mR_axis_tdata_reg[15:0];
  assign m00_axis_tdata[31:16] = mL_axis_tdata_reg[15:0];
  assign m00_axis_tvalid = m00_axis_tvalid_reg;

//
// logic for the ramp amplitude & sidetone volume multiplier. The ramp amplitude
// arrives as a stream but there is always valid data; ignore the stream and just take
// the data
// the width used for the multiplication c <= a*b; will be the widest of a, b and c
//  
  always @(posedge aclk)
  begin
    if(~aresetn)
    begin
// reset to start states
        ramp_amplitude_reg <= 0;
        sidetone_amplitude_reg <= 0;
        sidetone_vol_reg <= 0;
    end
    else		//!aresetn
    begin
        ramp_amplitude_reg <= s02_axis_tdata;
        sidetone_vol_reg <= sidetone_vol;
        sidetone_amplitude_reg <= ramp_amplitude_reg * sidetone_vol_reg;
    end         // if(!aresetn)
  end           // always @

//
// logic for the axi stream input buffers
// 2 separate axi stream registers. Coded lazily and therefore simply:
// each can accept an input transfer in one cycle and output transfer in the next
// but not one data beat per clock cycle.
//
  always @(posedge aclk)
  begin
    if(~aresetn)
    begin
// reset to start states. Deassert axi master and slave strobes; clear data registers
      s00_axis_tready_reg <= 1;                         // ready to accept transfers
      s00L_axis_tdata_reg <= 0;                         // left data is MSB
      s00R_axis_tdata_reg <= 0;                         // right data is LSB
      int00_axis_tvalid_reg <= 0;                       // no data held at reset
      s01_axis_tready_reg <= 1;
      s01_axis_tdata_reg <= 0;
      int01_axis_tvalid_reg <= 0;                       // no data held at reset
      
    end
    else		//!aresetn
    begin
// latch stream 0 (left, right audio)
      if(s00_axis_tvalid & s00_axis_tready_reg)             // complete a slave read
      begin
        s00L_axis_tdata_reg <= s00_axis_tdata[31:16];     // left data is MSB
        s00R_axis_tdata_reg <= s00_axis_tdata[15:0];      // right data is LSB
        s00_axis_tready_reg <= 0;                         // can't accept until consumed
        int00_axis_tvalid_reg <= 1;                       // data available
      end
// latch stream 1 (sidetone DDS)
      if(s01_axis_tvalid & s01_axis_tready_reg)           // complete a slave read
      begin
        s01_axis_tdata_reg <= s01_axis_tdata;             // latch the data
        s01_axis_tready_reg <= 0;                         // can't accept until consumed
        int01_axis_tvalid_reg <= 1;                       // data available
      end
// only pass on data to o/p buffer if both inputs have data, & output tready
      if(int00_axis_tvalid_reg & int01_axis_tvalid_reg & int_axis_tready_reg)     // data transferred out
      begin
        int00_axis_tvalid_reg <= 0;
        s00_axis_tready_reg <= 1;                         // can accept new data
        int01_axis_tvalid_reg <= 0;
        s01_axis_tready_reg <= 1;                         // ready for new data
      end
    end         // if(!aresetn)
  end           // always @


//
// logic for the axi stream output buffers
// more complex. needs to include the multiply operation; 
// and only process if both slave interfaces have data
//
  always @(posedge aclk)
  begin
    if(~aresetn)
    begin
// reset to start states. Deassert axi master and slave strobes; clear data registers
      mL_axis_tdata_reg <= 0;
      mR_axis_tdata_reg <= 0;
      m_axis_tdata_reg <= 0;
      int_axis_tready_reg <= 1;               // tready from stage 2 to stage 1
    end
    
    else
    begin
// take both data sources, multiply & add
      if(int00_axis_tvalid_reg & int01_axis_tvalid_reg & int_axis_tready_reg)     // accept data if available & ready
      begin
        scaled_sidetone_wire = sidetone_amplitude_reg * s01_axis_tdata_reg;
        mL_axis_tdata_reg <= s00L_axis_tdata_reg + scaled_sidetone_wire;
        mR_axis_tdata_reg <= s00R_axis_tdata_reg + scaled_sidetone_wire;
        int_axis_tready_reg <= 0;                       // can't accept until consumed
        m_axis_tvalid_reg <= 1;                         // data available
      end
      if(m_axis_tvalid_reg & m_axis_tready)             // data transferred out
      begin
        m_axis_tvalid_reg <= 0;
        int_axis_tready_reg <= 1;                         // can accept new data
      end
    end
  end           // always @

endmodule