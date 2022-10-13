//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    15.07.2021 17:18:01
// Design Name:    ddcmux.v
// Module Name:    AXIS_DDC_Multiplexer
// Project Name:   Saturn 
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    Module to interleave axi streams from DDC
// This is intended to interleave AXI streams from DDCs so that the correct number of
// words is transferred per data "beat". Input size is parameterised; output is 64 bits.
// if not enabled: passes no data to the master interface 
// when enabled, resets input FIFO then transfers words
//
// the IP processes the DDCConfig settings to know if each DDC is enabled, and what sample rate
// if 48KHz: transfer 1 sample
// if 96KHz: transfer 2 sample
// if 193KHz: transfer 4 sample
// if 384KHz: transfer 8 sample
// if 768KHz: transfer 16 sample
// if 1536KHz: transfer 32 sample
// if not enabled: read 1 sample (as DDC will be set to $8KHz) but don't pass to output

// 
// I/O signals:
//          aclk                master clock
//          aresetn             active low asynchronous reset signal
//          enabled             true if interface enabled; if false doesn't transfer 
//          DDCconfig           DDC config inputs
//          S00axisxxxx         10 input axi streams
//
//          active              true if data is being transferred
//          fiforstn            active low output if input FIFOs to be reset
//          DDCconfigout        DDC config values to be used by DDCs
//          M00axisxxxx         output axi stream
//
// DDC config values: 3 bits per DDC, starting at bits 2:0 for DDC 0
// top 2 bits not used
// xx999888777666555444333222111000
// input is from processor; output drive DDCs, so nsure they change at the right time
//
// Dependencies: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: 
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1 ns / 1 ps


module AXIS_DDC_Multiplexer #
(
  parameter AXIS_INPUT_SIZE = 48          // input bus width
)
(
  // System signals
  input wire                        aclk,
  input wire                        aresetn,

  // AXI stream Slave inputs
  input wire [AXIS_INPUT_SIZE-1:0]  s00_axis_tdata,      // input 0 stream
  input wire                        s00_axis_tvalid,
  output wire                       s00_axis_tready, 

  input wire [AXIS_INPUT_SIZE-1:0]  s01_axis_tdata,      // input 1 stream
  input wire                        s01_axis_tvalid,
  output wire                       s01_axis_tready, 

  input wire [AXIS_INPUT_SIZE-1:0]  s02_axis_tdata,      // input 2 stream
  input wire                        s02_axis_tvalid,
  output wire                       s02_axis_tready, 

  input wire [AXIS_INPUT_SIZE-1:0]  s03_axis_tdata,      // input 3 stream
  input wire                        s03_axis_tvalid,
  output wire                       s03_axis_tready, 

  input wire [AXIS_INPUT_SIZE-1:0]  s04_axis_tdata,      // input 4 stream
  input wire                        s04_axis_tvalid,
  output wire                       s04_axis_tready, 

  input wire [AXIS_INPUT_SIZE-1:0]  s05_axis_tdata,      // input 5 stream
  input wire                        s05_axis_tvalid,
  output wire                       s05_axis_tready, 

  input wire [AXIS_INPUT_SIZE-1:0]  s06_axis_tdata,      // input 6 stream
  input wire                        s06_axis_tvalid,
  output wire                       s06_axis_tready, 

  input wire [AXIS_INPUT_SIZE-1:0]  s07_axis_tdata,      // input 7 stream
  input wire                        s07_axis_tvalid,
  output wire                       s07_axis_tready, 

  input wire [AXIS_INPUT_SIZE-1:0]  s08_axis_tdata,      // input 8 stream
  input wire                        s08_axis_tvalid,
  output wire                       s08_axis_tready, 

  input wire [AXIS_INPUT_SIZE-1:0]  s09_axis_tdata,      // input 9 stream
  input wire                        s09_axis_tvalid,
  output wire                       s09_axis_tready, 


  // AXI stream master outputs
  output reg [63:0]                m_axis_tdata,        // output stream
  output reg                       m_axis_tvalid,
  input wire                        m_axis_tready, 

  
  // control signals
  input wire                        enabled,
  input wire [31:0]                 DDCconfig,            
  output reg [31:0]                 DDCconfigout = 0, 
  output reg active,                  // true when mux should be reset
  output reg fiforstn 

);

localparam ResetClockCount = 8;
localparam DDCChannels=10;
//
// input register and wire arrays 
//
  reg s_axis_tready [DDCChannels-1:0];          // array of stream input ready bits
  wire s_axis_tvalid [DDCChannels-1:0];         // array of stream input valid bits
  wire [AXIS_INPUT_SIZE-1:0] s_axis_tdata [DDCChannels-1:0]; // array of bus wires for data
//
// assign DDC input streams to arrays
// then we can access the input streams using array notation indexed by DDC number
//
  assign s00_axis_tready = s_axis_tready[0];    // tready outputs assigned to array reg
  assign s01_axis_tready = s_axis_tready[1];
  assign s02_axis_tready = s_axis_tready[2];
  assign s03_axis_tready = s_axis_tready[3];
  assign s04_axis_tready = s_axis_tready[4];
  assign s05_axis_tready = s_axis_tready[5];
  assign s06_axis_tready = s_axis_tready[6];
  assign s07_axis_tready = s_axis_tready[7];
  assign s08_axis_tready = s_axis_tready[8];
  assign s09_axis_tready = s_axis_tready[9];
  
  assign s_axis_tvalid[0] = s00_axis_tvalid;    // tvalid input copied to array of wires
  assign s_axis_tvalid[1] = s01_axis_tvalid;
  assign s_axis_tvalid[2] = s02_axis_tvalid;
  assign s_axis_tvalid[3] = s03_axis_tvalid;
  assign s_axis_tvalid[4] = s04_axis_tvalid;
  assign s_axis_tvalid[5] = s05_axis_tvalid;
  assign s_axis_tvalid[6] = s06_axis_tvalid;
  assign s_axis_tvalid[7] = s07_axis_tvalid;
  assign s_axis_tvalid[8] = s08_axis_tvalid;
  assign s_axis_tvalid[9] = s09_axis_tvalid;

  assign s_axis_tdata[0] = s00_axis_tdata;    // tdata input copied to array of wire vectors
  assign s_axis_tdata[1] = s01_axis_tdata;
  assign s_axis_tdata[2] = s02_axis_tdata;
  assign s_axis_tdata[3] = s03_axis_tdata;
  assign s_axis_tdata[4] = s04_axis_tdata;
  assign s_axis_tdata[5] = s05_axis_tdata;
  assign s_axis_tdata[6] = s06_axis_tdata;
  assign s_axis_tdata[7] = s07_axis_tdata;
  assign s_axis_tdata[8] = s08_axis_tdata;
  assign s_axis_tdata[9] = s09_axis_tdata;


//
// states for enabled sequencer
// state variable = enabledstate
//
localparam enidle = 0;                          // idle state
localparam enstarting = 1;                      // coming out of idle state
localparam enrunning = 2;                       // active
localparam enshutdown = 3;                      // shutting down

//
// states for DDC select sequencer
// state variable = ddcstate
//
localparam ddcidle = 0;                         // idle state
localparam ddcstart = 1;                        // coming out of idle state
localparam ddcenablemux = 2;                    // active
localparam ddcrun = 3;                          // shutting down

//
// states for stream mux sequencer
// state variable = muxstate
//
localparam muxidle = 0;                         // idle state
localparam muxddcwrite = 1;                     // start transferring DDC setting
localparam muxddclookup = 2;                    // lookup transfer count
localparam muxslvrdy = 3;                       // slave ready for transfer
localparam muxslvxfer = 4;                      // slave data transfer
localparam muxmstxfer = 5;                      // master aclk
localparam muxend = 6;                          // sequence aclk
localparam muxillegal = 7;                      // illegal state 

//
// internal registers
//
  reg internalactive = 0;                       // true if active state achieved
  reg [1:0] enabledstate = enidle;              // enable sequencer state
  reg [1:0] DDCstate = ddcidle;                 // DDC sequencer state
  reg [2:0] muxstate = muxidle;                 // multiplexer sequencer state
  reg [3:0] rstcounter = 0;                     // counter for reset duration 
  reg [5:0] samplecount = 0;                    // counter for sample transfer
  reg enablemux = 0;                            // true if o/p mux to be active
  reg muxactive = 0;                            // true if o/p mux provessing samples
  reg [3:0] DDCn;                               // DDC counter
  reg [31:0] DDCrates;                          // internal count of DDC rates          


//
// logic for "enabled" sequencer
//  When “Enabled” changed to asserted:
//      Assert fiforstn for 8 clocks
//      Assert “Active”
//      Assert “InternalActive”
//  When “Enabled” changed to deasserted:
//      Deassert “InternalActve”
//      Wait until all DDCState == 0 (DDCs have been serviced)
//      Deassert “Active”
//
    always @(posedge aclk)
    begin
        if (~aresetn)                   // reset processing
        begin
            fiforstn <= 0;
            enabledstate <= enidle;
            internalactive <= 0;
            active=0;
        end
        
        else                            // normal processing
        begin
            case (enabledstate)
                enidle: begin                               // idle state
                    if(enabled == 1)
                    begin
                        active <= 1;                        // set active
                        enabledstate <= enstarting;         // advance to start state
                        fiforstn <= 0;                      // assert fifo reset
                        internalactive <= 0;                // not active
                        rstcounter <= (ResetClockCount-1);  // load countdown
                    end
                    else
                    begin
                        active <= 0;                        // not active
                        internalactive <= 0;                // not active
                        fiforstn <= 1;                      // no fifo reset
                    end
                end
                
                enstarting: begin                           // counting reset asserted
                if(rstcounter==0)
                begin
                    internalactive <= 1;                    // set active
                    enabledstate <= enrunning;              // advance to operating state
                    fiforstn <= 1;                          // no fifo reset
                end
                else
                    rstcounter <= rstcounter-1;
                end
    
                enrunning: begin                            // operate
                    if(enabled == 0)
                    begin
                        enabledstate <= enshutdown;         // advance to start state
                        internalactive <= 0;                // not active
                    end
                end
    
                enshutdown: begin                           // "shutting down" state
                    if(DDCstate == ddcidle)                       // sequencer has shut down
                    begin
                        enabledstate <= enidle;             // advance to idle state
                        active <= 0;                        // not active
                    end
                end

            endcase
        end
    end




//
// logic for "DDC Select" sequencer
//
//  When “InternalActive” is changed to asserted:
//      Set DDCState to 1
//      Copy DDC settings to output
//      Initiate Stream Sequencer to Transmit a DDC config word to the output FIFO by setting DDCx=15
//      For DDCx= 1 to 10
//          Initiate Stream sequencer to transfer samples from DDC number DDCx
//          If DDC enabled: Read out the required number of data bytes to output FIFO
//          If DDC disabled: read out required number of samples and discard
//          Wait till muxstate == muxend
//      At end of DDCs:
//          Check if InternalActive asserted
//          If deasserted, revert to idle
//          Else continue at state 1
//
    always @(posedge aclk)
    begin
        if (~aresetn)                   // reset processing
        begin
            DDCstate <= ddcidle;        // initial state
            enablemux <= 0;             // mux inactive
            DDCn <= 0;                  // DDC = 0
            DDCrates <= 0;              // clear sample rates
            DDCconfigout <= 0;          // clear DDCs all to inactive
        end
        
        else                            // normal processing
        begin
            case (DDCstate)
                ddcidle: begin          // initial state: see if released to start
                    if(internalactive == 1)
                        DDCstate <= ddcstart;
                end

                ddcstart: begin
                    DDCn <= 15;          // clear DDC number; point to config setting
                    DDCconfigout <= DDCconfig;
                    DDCrates <= DDCconfig;
                    DDCstate <= ddcenablemux;
                end

                ddcenablemux: begin
                    enablemux <= 1;             // mux active
                    DDCstate <= ddcrun;
                end

                ddcrun: begin
                    if(muxstate == muxend)              // if mux operation has ended
                    begin
                        enablemux <= 0;                 // set mux to disabled, so its state clears to 0
                        DDCstate <= ddcenablemux;
                        if(DDCn == 9)                   // if finished this set of DDC:
                        begin
                            if(internalactive == 0)     // if sequencer halted excternall, go back to idle
                                DDCstate <= ddcidle;
                             else                       // else restart sequence
                                DDCstate <= ddcstart;
                        end
                        else if(DDCn == 15)             // if just done config word
                            DDCn <= 0;
                        else
                        begin
                            DDCn <= DDCn + 1;
                            DDCrates <= (DDCrates >> 3);        // shift to next DDC setting
                        end
                    end
                end

            endcase
        end
    end




//
// logic for stream sequencer
//
//  If EnableMux == 0, stay in idle
//  Enter state 1
//  Set MuxActive
//  If DDCx == 15:
//      Set top 16 bits for DDC config word
//      Transfer output word
//      Clear MuxActive
//      Go to idle state 0
//  If DDCx == 0 to 9:
//      DDCToProcess = DDCx
//      Read DDC config (3 bits)
//      Look up TransferCount
//      For SampleCount == 0 to (TransferCount-1)
//          Read input word
//          If Active, initiate output transfer
//      Clear MuxActive
//      Go to idle state 0
//
    always @(posedge aclk)
    begin
        if (~aresetn)                   // reset processing
        begin
            m_axis_tdata <= 0;          // clear output data
            m_axis_tvalid <= 0;         // cleaqr output valid
            s_axis_tready[0] <= 0;      // not ready for input data
            s_axis_tready[1] <= 0;      // not ready for input data
            s_axis_tready[2] <= 0;      // not ready for input data
            s_axis_tready[3] <= 0;      // not ready for input data
            s_axis_tready[4] <= 0;      // not ready for input data
            s_axis_tready[5] <= 0;      // not ready for input data
            s_axis_tready[6] <= 0;      // not ready for input data
            s_axis_tready[7] <= 0;      // not ready for input data
            s_axis_tready[8] <= 0;      // not ready for input data
            s_axis_tready[9] <= 0;      // not ready for input data
            muxactive <= 0;             // multiplexer not active
            muxstate <= muxidle;        // idle state
        end
        
        else                            // normal processing
        begin
            case (muxstate)
                muxidle: begin          // initial state: see if released to start
                    if(enablemux)       // if multiplexer should become active
                    begin
                        muxactive <= 1;
                        if(DDCn == 15)      // process DDC settings
                            muxstate <= muxddcwrite;
                        else
                            muxstate <= muxddclookup;
                    end
                end
                
                muxddcwrite: begin                // transfer DDC settings
                    if(m_axis_tvalid == 0)              // start of transfer cycle
                    begin
                        m_axis_tdata[63:48] <= 16'b1000000000000000;
                        m_axis_tdata[47:32] <= 0;
                        m_axis_tdata[31:0] <= DDCconfigout;
                        m_axis_tvalid <= 1;
                        end
                    else if(m_axis_tready && m_axis_tvalid)         // if transfer complete
                    begin
                        m_axis_tvalid <= 0;                         // clear transfer request
                        muxactive <= 0;
                        muxstate <= muxend;                              // go to wait till command removed
                    end
                end
                   
                muxddclookup: begin                // initiate transfer data for DDCn: lookup count
                case (DDCrates[2:0])
                    0: samplecount <= 0;                    // disabled DDC
                    1: samplecount <= 0;                    // 48KHz DDC
                    2: samplecount <= 1;                    // 96KHz DDC
                    3: samplecount <= 3;                    // 192KHz DDC
                    4: samplecount <= 7;                    // 384KHz DDC
                    5: samplecount <= 15;                   // 768KHz DDC
                    6: samplecount <= 31;                   // 1536KHz DDC
                    7: samplecount <= 31;                   // 1536KHz DDC
                endcase
                muxstate <= muxslvrdy;                              // go to "process samples" state
                end
                
                muxslvrdy: begin                // transfer data for DDCn
                    s_axis_tready[DDCn] <= 1;               // assert reasy to initiate transfer
                    muxstate <= muxslvxfer;
                end
                
                muxslvxfer: begin                // transfer data for DDCn
                    if(s_axis_tready[DDCn] && s_axis_tvalid[DDCn])      // if input transfer complete
                    begin
                        m_axis_tdata[63:48] <= 16'b0;
                        m_axis_tdata[47:0] <= s_axis_tdata[DDCn];
                        s_axis_tready[DDCn] <= 0;               // deassert reasy to initiate transfer
                        if(DDCrates[2:0] == 0)                  // if o/p transfer disabled, see if complete
                        begin
                            if(samplecount == 0)                // if complete, deassert active & goto wait
                            begin
                                muxactive <= 0;
                                muxstate <= muxend;
                            end
                            else                                // decrement sample count and loop for next sample
                            begin
                                samplecount <= (samplecount-1);
                                muxstate <= muxslvrdy;
                            end
                        end
                        else                                    // start output transfer
                        begin
                            m_axis_tvalid <= 1;
                            muxstate <= muxmstxfer;
                        end
                    end
                end
                
                muxmstxfer: begin                // transfer data for DDCn
                    if(m_axis_tvalid && m_axis_tready)
                    begin
                        m_axis_tvalid <= 0;                     // deassert valid
                        if(samplecount == 0)                // if complete, deassert active & goto wait
                        begin
                            muxactive <= 0;
                            muxstate <= muxend;
                        end
                        else                                // decrement sample count and loop for next sample
                        begin
                            samplecount <= (samplecount-1);
                            muxstate <= muxslvrdy;
                        end
                    end
                end
                
                muxend: begin                // close down - wait till enable=0 then goto idle
                    if(enablemux == 0)
                        muxstate <= muxidle;
                end
                
                muxillegal: begin                                    // unused state
                muxstate <= muxidle;
                end
                
            endcase
                
        end
    end





endmodule