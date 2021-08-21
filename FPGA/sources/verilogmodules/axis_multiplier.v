//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    15.07.2021 17:18:01
// Design Name:    axis_multiplier.v
// Module Name:    axis_multiplier 
// Project Name:   Saturn 
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    Module to multiply two signed values

//
// in the planned use, this will be throttled mostly by tready
// 
// I/O signals:
//          aclk                master clock
//          aresetn             asynchronous reset signal
//          s0_axis_xxxxx       A input balue
//          s1_axis_xxxxx       B input value
//          m_axis_xxxxx        A*B output value
//
// Dependencies: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: 
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1 ns / 1 ps


module axis_multiplier #
(parameter S00Size = 16, S01Size = 16, MSize = 16)
(
  // System signals
(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK" *)
(* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET aresetn" *)
(* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s00_axis:s01_axis:m_axis" *)
  input wire                    aclk,
(* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
(* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input wire                    aresetn,

  // AXI stream Slave inputs
  input wire [S00Size-1:0]      s00_axis_tdata,      // A value
  input wire                    s00_axis_tvalid,
  output wire                   s00_axis_tready, 

  input wire [S01Size-1:0]      s01_axis_tdata,      // B value
  input wire                    s01_axis_tvalid,
  output wire                   s01_axis_tready, 
  
  // AXI stream master outputs
  output wire [MSize-1:0]       m_axis_tdata,      	// L/R audio samples to Codec (L=MSB)
  output wire                   m_axis_tvalid,
  input wire                    m_axis_tready 
);
//
// internal registers
//
//
// axi stream input registers
//
  reg signed [S00Size-1:0] s00_axis_tdata_reg;
  reg signed [S01Size-1:0] s01_axis_tdata_reg;
  reg s00_axis_tready_reg;
  reg s01_axis_tready_reg;
  reg int00_axis_tvalid_reg;                // tvalid from stage 1 to stage 2
  reg int01_axis_tvalid_reg;                // tvalid from stage 1 to stage 2

//
// axi stream output registers
//
  reg signed [MSize-1:0] m_axis_tdata_reg;
  reg m_axis_tvalid_reg;
  reg int_axis_tready_reg;                  // tready from stage 2 to stage 1

  assign s00_axis_tready = s00_axis_tready_reg;
  assign s01_axis_tready = s01_axis_tready_reg;
  assign m_axis_tdata = m_axis_tdata_reg;
  assign m_axis_tvalid = m_axis_tvalid_reg;

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
      s00_axis_tdata_reg <= 0;                          // A value
      int00_axis_tvalid_reg <= 0;                       // no data held at reset
      s01_axis_tready_reg <= 1;
      s01_axis_tdata_reg <= 0;                          // B value
      int01_axis_tvalid_reg <= 0;                       // no data held at reset
      
    end
    else		//!aresetn
    begin
// latch stream 0 (A value)
      if(s00_axis_tvalid & s00_axis_tready_reg)             // complete a slave read
      begin
        s00_axis_tdata_reg <= s00_axis_tdata;             // A value
        s00_axis_tready_reg <= 0;                         // can't accept until consumed
        int00_axis_tvalid_reg <= 1;                       // data available
      end
// latch stream 1 (B value)
      if(s01_axis_tvalid & s01_axis_tready_reg)           // complete a slave read
      begin
        s01_axis_tdata_reg <= s01_axis_tdata;             // B value
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
// logic for the axi stream output buffer
// only process if both slave interfaces have data
//
  always @(posedge aclk)
  begin
    if(~aresetn)
    begin
// reset to start states. Deassert axi master and slave strobes; clear data registers
      m_axis_tdata_reg <= 0;
      m_axis_tvalid_reg <= 0;
      int_axis_tready_reg <= 1;               // tready from stage 2 to stage 1
    end
    
    else
    begin
// take both data sources, multiply & add
      if(int00_axis_tvalid_reg & int01_axis_tvalid_reg & int_axis_tready_reg)     // accept data if available & ready
      begin
        m_axis_tdata_reg <= s00_axis_tdata_reg * s01_axis_tdata_reg;
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