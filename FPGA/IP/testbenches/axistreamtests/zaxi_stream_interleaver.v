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
// I/O signals:
//          aclk                master AXIS_Interleaver
//          aresetn             asynchronous reset signal
//          interleave          true if to interleave AXIS_Interleaver
//          enabled             true if interface enabled; if false doesn't transfer AXIS_Interleaver
//
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: 
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1 ns / 1 ps


module AXIS_Interleaver #
(
  parameter SAXIS_SIZE = 24,          // input bus width
  parameter MAXIS_SIZE = 24          // output bus width
)
(
  // System signals
  input wire                       aclk,
  input wire                       aresetn,
  input wire                       interleave,    // 1if interleave; 0 if propagate
  input wire                       enabled,

  // AXI stream Slave inputs
  input wire [SAXIS_SIZE-1:0]      s00_axis_tdata,      // input A stream
  input wire                       s00_axis_tvalid,
  output wire                      s00_axis_tready, 

  input wire [SAXIS_SIZE-1:0]      s01_axis_tdata,      // input B stream
  input wire                       s01_axis_tvalid,
  output wire                      s01_axis_tready, 
  
  // AXI stream master outputs
  output wire [MAXIS_SIZE-1:0]     m00_axis_tdata,      // output A stream
  output wire                      m00_axis_tvalid,
  input wire                       m00_axis_tready, 

  output wire [MAXIS_SIZE-1:0]     m01_axis_tdata,      // output B stream
  output wire                      m01_axis_tvalid,
  input wire                       m01_axis_tready, 
     
  
  // control signals
  output wire mux_reset,                  // true when mux should be reset
  output wire is_interleaved 

);
//
// internal registers
//
  reg interleavedreg = 0;                       // true if inter leved outputs
  reg enablestreamreg = 0;
  reg muxresetreg = 0;
  reg [1:0]ctrl_state = 2'b00;                  // sequencer for control  
//
// axi stream input registers
//
  reg [SAXIS_SIZE-1:0] s00_axis_tdata_reg;
  reg [SAXIS_SIZE-1:0] s01_axis_tdata_reg;
  reg s00_axis_tready_reg;
  reg s01_axis_tready_reg;

//
// axi stream output registers
//
  reg [MAXIS_SIZE-1:0] m00_axis_tdata_reg;
  reg [MAXIS_SIZE-1:0] m01_axis_tdata_reg;
  reg m00_axis_tvalid_reg;
  reg m01_axis_tvalid_reg;

  assign is_interleaved = interleavedreg;       // temp debug output
  assign mux_reset = muxresetreg;

  assign s00_axis_tready = s00_axis_tready_reg;
  assign s01_axis_tready = s01_axis_tready_reg;
  assign m00_axis_tdata = m00_axis_tdata_reg;
  assign m01_axis_tdata = m01_axis_tdata_reg;
  assign m00_axis_tvalid = m00_axis_tvalid_reg;
  assign m01_axis_tvalid = m01_axis_tvalid_reg;
//
// logic for the control sequencer. 
// if not enabled, halt all activity;
// when enable asserted, clear FIFOs then enable data transfer
//  
  always @(posedge aclk)
  begin
    if(~aresetn)
    begin
// reset to start states
      interleavedreg <= 0;
      enablestreamreg <= 0;
      muxresetreg <= 1;
      ctrl_state <= 2'b00;
    end
    else		//!aresetn
    begin

      if(enabled == 0)
      begin
        ctrl_state<= 2'b00;
        interleavedreg <= 0;
        enablestreamreg <= 0;
        muxresetreg <= 1;
      end
      else
        case (ctrl_state)
            0: begin                    // exit reset state
              if(enabled == 1)
                ctrl_state = 2'b01;
            end

            1: begin
              muxresetreg <= 0;         // deassert reset
              ctrl_state <= 2'b10;
            end

            2: begin
              interleavedreg <= is_interleaved;     // normal operation
              enablestreamreg <= 1;
              ctrl_state <= 2'b11;
            end

            3: begin                                // "operate" state
            end
      endcase
    end         // if(!aresetn)
  end           // always @

//
// logic for the axi stream input buffers
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
      s00_axis_tready_reg <= 1;                         // ready to accept transfers
      s01_axis_tready_reg <= 1;
      s00_axis_tdata_reg <= 0;
      s01_axis_tdata_reg <= 0;
    end
    else		//!aresetn
    begin
// stream 0
      if(s00_axis_tvalid & s00_axis_tready_reg)         // complete a slave read
      begin
        m00_axis_tdata_reg <= s00_axis_tdata;           // latch the data
        if(enablestreamreg)                             // if transferring data
        begin
          s00_axis_tready_reg <= 0;                     // can't accept until consumed
          m00_axis_tvalid_reg <= 1;                     // data available
        end
      end
      if(m00_axis_tvalid_reg & m00_axis_tready)         // complete a master write
      begin
        m00_axis_tvalid_reg <= 0;
        s00_axis_tready_reg <= 1;                       // can accept new data
      end
// stream 1
      if(s01_axis_tvalid & s01_axis_tready_reg)         // complete a slave read
      begin
        m01_axis_tdata_reg <= s01_axis_tdata;           // latch the data
        if(enablestreamreg)                             // if transferring data
        begin
          s01_axis_tready_reg <= 0;                     // can't accept until consumed
          m01_axis_tvalid_reg <= 1;                     // data available
        end
      end
      if(m01_axis_tvalid_reg & m01_axis_tready)         // complete a master write
      begin
        m01_axis_tvalid_reg <= 0;
        s01_axis_tready_reg <= 1;                       // ready for new data
      end
    end         // if(!aresetn)
  end           // always @

endmodule