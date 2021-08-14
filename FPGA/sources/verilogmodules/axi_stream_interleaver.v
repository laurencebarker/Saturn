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
// This is intended to either pass separately or interleave the output of two DDCs 
// if not enabled: passes no data to the master interface, 
// but accepts all samples at the slave interface (discarding data, so DSP doesn't stall)
// if enabled, not interleaved: just buffers two separate streams (DDC1, DDC0 are separate)
// if enabled and interleaved: interleaves DDC0 & DDC1 samples onto DDC0 output
// to change over:
// set enabled = 0; set intereaved bit; set enabled = 1
//
// inteleave=0:
// S01-> M01
// S00-> M00
//
// interleave=1, oddbeat=0:           interleave=1, oddbeat=1:
// S01 -> no xfer                     S01 -> M00
// S00 -> M00                         S00 -> no xfer
//

// 
// I/O signals:
//          aclk                master clock
//          aresetn             asynchronous reset signal
//          interleave          true if to interleave 
//          enabled             true if interface enabled; if false doesn't transfer 
//
// Dependencies: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: 
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1 ns / 1 ps


module AXIS_Interleaver #
(
  parameter AXIS_SIZE = 48          // input bus width
)
(
  // System signals
  input wire                       aclk,
  input wire                       aresetn,
  input wire                       interleave,    // 1if interleave; 0 if propagate
  input wire                       enabled,

  // AXI stream Slave inputs
  input wire [AXIS_SIZE-1:0]       s00_axis_tdata,      // input A stream
  input wire                       s00_axis_tvalid,
  output wire                      s00_axis_tready, 

  input wire [AXIS_SIZE-1:0]       s01_axis_tdata,      // input B stream
  input wire                       s01_axis_tvalid,
  output wire                      s01_axis_tready, 
  
  // AXI stream master outputs
  output wire [AXIS_SIZE-1:0]      m00_axis_tdata,      // output A stream
  output wire                      m00_axis_tvalid,
  input wire                       m00_axis_tready, 

  output wire [AXIS_SIZE-1:0]      m01_axis_tdata,      // output B stream
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
  reg oddbeat = 0;                              // alternate even/odd. Steam 0 if oddbeat=0;
  reg [1:0]ctrl_state = 2'b00;                  // sequencer for control  
//
// axi stream input registers
//
  reg [AXIS_SIZE-1:0] s00_axis_tdata_reg;
  reg [AXIS_SIZE-1:0] s01_axis_tdata_reg;
  reg s00_axis_tready_reg;
  reg s01_axis_tready_reg;
  reg int00_axis_tvalid_reg;                // tvalid from stage 1 to stage 2
  reg int01_axis_tvalid_reg;                // tvalid from stage 1 to stage 2

//
// axi stream output registers
//
  reg [AXIS_SIZE-1:0] m00_axis_tdata_reg;
  reg [AXIS_SIZE-1:0] m01_axis_tdata_reg;
  reg m00_axis_tvalid_reg;
  reg m01_axis_tvalid_reg;
  reg int00_axis_tready_reg;                // tready from stage 1 to stage 2
  reg int01_axis_tready_reg;                // tready from stage 1 to stage 2

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
              interleavedreg <= interleave;         // normal operation
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
      s01_axis_tready_reg <= 1;
      s00_axis_tdata_reg <= 0;
      s01_axis_tdata_reg <= 0;
      int00_axis_tvalid_reg <= 0;                       // no data held at reset
      int01_axis_tvalid_reg <= 0;                       // no data held at reset
      
    end
    else		//!aresetn
    begin
// stream 0
      if(s00_axis_tvalid & s00_axis_tready_reg)             // complete a slave read
      begin
        s00_axis_tdata_reg <= s00_axis_tdata;               // latch the data
        if(enablestreamreg)                                 // if transferring data
        begin
          s00_axis_tready_reg <= 0;                         // can't accept until consumed
          int00_axis_tvalid_reg <= 1;                       // data available
        end
      end
      if(int00_axis_tvalid_reg & int00_axis_tready_reg)     // complete a master write
      begin
        int00_axis_tvalid_reg <= 0;
        s00_axis_tready_reg <= 1;                           // can accept new data
      end
// stream 1
      if(s01_axis_tvalid & s01_axis_tready_reg)             // complete a slave read
      begin
        s01_axis_tdata_reg <= s01_axis_tdata;               // latch the data
        if(enablestreamreg)                                 // if transferring data
        begin
          s01_axis_tready_reg <= 0;                         // can't accept until consumed
          int01_axis_tvalid_reg <= 1;                       // data available
        end
      end
      if(int01_axis_tvalid_reg & int01_axis_tready_reg)     // complete a master write
      begin
        int01_axis_tvalid_reg <= 0;
        s01_axis_tready_reg <= 1;                           // ready for new data
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
      int00_axis_tready_reg <= 1;               // tready from stage 2 to stage 1
      int01_axis_tready_reg <= 1;               // tready from stage 2 to stage 1
      oddbeat <= 0;                             // point to stream 0 
    end
    
    else if(ctrl_state != 2'b11)                            // if not fully enabled, reset the beat
//
// if we change over mode,  hold in appropriate states
//
    begin
      oddbeat <= 0;                                         // reset the multiplexing action
      int00_axis_tready_reg <= 1;                           // tready from stage 1 to stage 2 asserted
      if(interleave  == 0)
          int01_axis_tready_reg <= 1;                       // assert stream 1 tready if not multiplexed
      else
          int01_axis_tready_reg <= 0;
    end
    
    else if(interleavedreg==0)		// "straight through" non interleaved streams
//
// non interleaved mode: separate output stream registers, each serving an input register
// it starts with tready asserted to stage 1
//
    begin
// stream 0
      if(int00_axis_tvalid_reg & int00_axis_tready_reg)     // accept data if available & ready
      begin
        m00_axis_tdata_reg <= s00_axis_tdata_reg;           // latch the data
        if(enablestreamreg)                                 // if transferring data
        begin
          int00_axis_tready_reg <= 0;                       // can't accept until consumed
          m00_axis_tvalid_reg <= 1;                         // data available
        end
      end
      if(m00_axis_tvalid_reg & m00_axis_tready)             // complete a master write
      begin
        m00_axis_tvalid_reg <= 0;
        int00_axis_tready_reg <= 1;                         // can accept new data
      end
// stream 1
      if(int01_axis_tvalid_reg & int01_axis_tready_reg)         // complete a slave read
      begin
        m01_axis_tdata_reg <= s01_axis_tdata_reg;           // latch the data
        if(enablestreamreg)                                 // if transferring data
        begin
          int01_axis_tready_reg <= 0;                       // can't accept until consumed
          m01_axis_tvalid_reg <= 1;                         // data available
        end
      end
      if(m01_axis_tvalid_reg & m01_axis_tready)             // output data taken from register
      begin
        m01_axis_tvalid_reg <= 0;
        int01_axis_tready_reg <= 1;                         // ready for new data
      end
    end         // if(!interleavedreg)
    else
//
// interleaved mode: multiplex both streams into M00
// the behaviour is divided into even cycles (data from S00) and odd cycles (data from S01)
//
    begin       // we are interleaved, so multiplex the two streams
      m01_axis_tvalid_reg = 0;                              // no output data from unused 
      if(oddbeat == 0)                          // even cycle - stream 0 data
      begin
        if(int00_axis_tvalid_reg & int00_axis_tready_reg)     // accept data if available & ready
        begin
          m00_axis_tdata_reg <= s00_axis_tdata_reg;           // latch the data
          if(enablestreamreg)                                 // if transferring data
          begin
            int00_axis_tready_reg <= 0;                       // can't accept until consumed
            m00_axis_tvalid_reg <= 1;                         // data available
          end
        end
        if(m00_axis_tvalid_reg & m00_axis_tready)             // data transferred from o/p register
        begin
          m00_axis_tvalid_reg <= 0;
          int01_axis_tready_reg <= 1;                         // can accept new data - S01 next
          oddbeat <= 1;                                       // odd beat is next
        end
      end
      else                                  // odd cycle - take stream 1 data
      begin
        if(int01_axis_tvalid_reg & int01_axis_tready_reg)     // accept data if available & ready
        begin
          m00_axis_tdata_reg <= s01_axis_tdata_reg;           // latch the data
          if(enablestreamreg)                                 // if transferring data
          begin
            int01_axis_tready_reg <= 0;                       // can't accept until consumed
            m00_axis_tvalid_reg <= 1;                         // data available
          end
        end
        if(m00_axis_tvalid_reg & m00_axis_tready)             // data transferred from o/p register
        begin
          m00_axis_tvalid_reg <= 0;
          int00_axis_tready_reg <= 1;                         // can accept new data from S00
          oddbeat <= 0;                                       // and even beat next
        end
      end
    end         // interleaved
  end           // always @

endmodule