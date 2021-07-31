//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    29.07.2021 19:30
// Design Name:    axi_stream_resizer.v
// Module Name:    AXIS_Sizer_64to48
// Project Name:   Saturn 
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    Module to resize an axi stream from 64 to 48 bits
// achieved by demultiplexing to 192 bits, then multiplexing back
// this block is intended to connect direct to a FIFO at the input
// and to DSP at the output 
// input and output are compliant axi streams with ready and valid
// the demux/mux is resettable so it can be put back onto beat 0
// in ther application data will write in from a FIFO much faster
// than data is read out; so it must accept back pressure
//
// 
// I/O signals:
//          aclk                master clock
//          aresetn             asynchronous reset signal
//          mux_reset           if 1, the demux and mux are reset to beats 0
//
//          s_axis_xxxxx        64 bit input stream
//          m_axis_xxxxx        48 bit output stream
//
// the implementation will have:
//
//    64 bit            192 bit             192 bit             48 bit
//    input   -->       demux     -->       mux       -->       output
//    AXI               register            register            AXI
//    register                                                  register
//            ------>            ------> 
//        axis_tvalid_reg     demux_valid_reg
//
//            <-----             <------ 
//        demux_ready_reg      mux_ready_reg
//        
//                      beat                beat
//                      0: W0-47            0: R0-47
//                      1: W49-95           1: R48-95
//                      2: W96-143          2: R143-96
//                      3:wait              3: R191:144
//
// Dependencies: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: 
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1 ns / 1 ps


module AXIS_Sizer_64to48
(
  // System signals
  input wire             aclk,
  input wire             aresetn,
  input wire             mux_reset,    // 1 if rset; 0 to operate

  // AXI stream Slave inputs
  input wire [63:0]      s_axis_tdata,      // input A stream
  input wire             s_axis_tvalid,
  output wire            s_axis_tready, 

  
  // AXI stream master outputs
  output wire [47:0]     m_axis_tdata,      // output A stream
  output wire            m_axis_tvalid,
  input wire             m_axis_tready 

     
);
//
// internal registers
//
  reg [1:0]input_beat = 2'b00;                  // sequencer for control  
  reg [1:0]output_beat = 2'b00;                 // sequencer for control  
//
// axi stream input registers
//
  reg [63:0] s_axis_tdata_reg;
  reg s_axis_tvalid_reg;
  reg s_axis_tready_reg;
  

//
// axi stream output registers
//
  reg [47:0] m_axis_tdata_reg;
  reg m_axis_tready_reg;                        // read from input stage
  reg m_axis_tvalid_reg;                        // valid signal to demux reg
  
//
// intermediate registers
//  
  reg demux_valid_reg;                          // 1 if demux has word to hand over to o/p
  reg demux_ready_reg;                          // 1 if demux ready to accept new data from i/p
  reg mux_ready_reg;                            // 1 if mux ready to accept new data from demux
  reg [191:0] demux_data_reg;                   // data being demultiplexed
  reg [191:0] mux_data_reg;                     // data being multiplexed
  
  

  assign s_axis_tready = s_axis_tready_reg;
  assign m_axis_tdata = m_axis_tdata_reg;
  assign m_axis_tvalid = m_axis_tvalid_reg;

//
// logic for the axi stream input buffer
// single axi stream register. Coded lazily and therefore simply:
// it accept an input transfer in one cycle and output transfer in the next
// but not one data beat per clock cycle.
//
  always @(posedge aclk)
  begin
    if(~aresetn)
    begin
// reset to start states. Deassert axi master and slave strobes; clear data registers
      s_axis_tready_reg <= 1;                           // ready to accept transfers
      s_axis_tdata_reg <= 0;
      s_axis_tvalid_reg <= 0;                           // valid out: no data held at reset
    end
    else		//!aresetn
    begin
      if(s_axis_tvalid & s_axis_tready_reg)             // complete a slave read
      begin
        s_axis_tdata_reg <= s_axis_tdata;               // latch the data
        s_axis_tready_reg <= 0;                         // can't accept until consumed
        s_axis_tvalid_reg <= 1;                         // data available to demux
      end
      if(s_axis_tvalid_reg & demux_ready_reg)           // if demux has been given data
      begin
        s_axis_tvalid_reg <= 0;                         // (data always accepted in 1 cycle)
        s_axis_tready_reg <= 1;                         // can accept new data
      end
    end         // if(!aresetn)
  end           // always @



//
// logic for the demultiplexer from 48 to 192 bits
// only need sto act if vailid from inpu register is set
// depending on the beat, write the input register to part of the multiplexer register 
//
  always @(posedge aclk)
  begin
    if(~aresetn | mux_reset)                            // master or externall applied reset
    begin
      demux_data_reg <= 0;                              // clear the demux register
      input_beat <= 2'b00;                              // beat clonter to 1st beat
      demux_valid_reg <= 0;                             // no data to pass forward
      demux_ready_reg <= 1;                             // ready to accept new data
    end
    else		//!aresetn
    begin
      //
      // in each beat, write the next stage of the register.
      // signal the next stage mltiplexer when we are on beat 3
      //
      case(input_beat)
        2'b00: 
          if(s_axis_tvalid_reg)         // if input data available
          begin
            demux_data_reg[63:0] <= s_axis_tdata_reg[63:0];
            input_beat <= input_beat + 1;
            demux_ready_reg <= 1;       // can accept more data
          end
        2'b01:
          if(s_axis_tvalid_reg)         // if input data available
          begin
            demux_data_reg[127:64] <= s_axis_tdata_reg[63:0];
            input_beat <= input_beat + 1;
            demux_ready_reg <= 1;       // can accept more data
          end
        2'b10:
          if(s_axis_tvalid_reg)         // if input data available
          begin
            demux_data_reg[191:128] <= s_axis_tdata_reg[63:0];
            input_beat <= input_beat + 1;
            demux_ready_reg <= 0;       // can NOT accept more data
            demux_valid_reg <= 1;       // we have output data available
          end
        2'b11:
          // wait in this state until we've handed off the output data
          if(demux_valid_reg & mux_ready_reg)
          begin
            input_beat <= 0;
            demux_valid_reg <= 0;       // output data taken, so not available now
            demux_ready_reg <= 1;       // we can accept input data next clock
          end
      endcase
    end         // if(!aresetn)
  end           // always @


//
// logic for the multiplexer and axi stream output buffers
//
  always @(posedge aclk)
  begin
    if(~aresetn | mux_reset)
    begin
// reset to start states. Deassert axi master and slave strobes; clear data registers
      output_beat <= 2'b11;                      // hold in "no data" state
      m_axis_tvalid_reg <= 0;
      m_axis_tdata_reg <= 0;
      mux_data_reg <= 0;
      mux_ready_reg <= 1;                       // ready to accept data
    end
    else        //!reset
    begin
      if( demux_valid_reg & mux_ready_reg)                  // 1st latch new data if we have it
      begin
        mux_data_reg[191:0] <= demux_data_reg[191:0];       // copy in new data
        output_beat <= 2'b00;                               // go to start state
        mux_ready_reg <= 0;                                 // can't accpt new data
      end
      if(!m_axis_tvalid_reg & !mux_ready_reg)               // able to transfer data out
      begin
        case(output_beat)
          2'b00: m_axis_tdata_reg[47:0] <=  mux_data_reg[47:0];           // latch the data
          2'b01: m_axis_tdata_reg[47:0] <=  mux_data_reg[95:48];           // latch the data
          2'b10: m_axis_tdata_reg[47:0] <=  mux_data_reg[143:96];           // latch the data
          2'b11: m_axis_tdata_reg[47:0] <=  mux_data_reg[191:144];           // latch the data
        endcase
        m_axis_tvalid_reg <= 1;                             // can't accept until consumed
      end
      if(m_axis_tvalid_reg & m_axis_tready)                 // data transferred out from o/p reg
      begin
        m_axis_tvalid_reg <= 0;                             // deassert output ready
        if(output_beat!= 2'b11)                             // and move to next data
          output_beat <= output_beat + 1;
        else
          mux_ready_reg <= 1;                               // ready for new data
      end
    end         // if(!reset)
  end           // always @

endmodule