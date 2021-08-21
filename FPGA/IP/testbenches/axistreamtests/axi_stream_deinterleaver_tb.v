//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    16.08.2021
// Design Name:    axi_stream_deinterleaver_tb.v
// Module Name:    AXIS_Deinterleaver_tb
// Project Name:   Saturn 
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    testbench for axi stream deinterleaver 
//
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: 
// 
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps
  
module axi_stream_deinterleaver_tb();
  
////////////////////////////////////////////////////////////////////////////////// 
// axi stream deinterleaver Test Bench Signals
// use wire to connect a module output
// use reg to connect a module input
//////////////////////////////////////////////////////////////////////////////////  
  reg aclk=0;
  reg aresetn=1;
  reg deinterleave;
  reg enabled;

  reg [23:0] s_axis_tdata;      // input A stream
  reg        s_axis_tvalid;
  wire       s_axis_tready; 

  // AXI stream master outputs
  wire [23:0] m00_axis_tdata;      // output A stream
  wire        m00_axis_tvalid;
  reg         m00_axis_tready; 

  wire [23:0] m01_axis_tdata;      // output B stream
  wire        m01_axis_tvalid;
  reg         m01_axis_tready; 
       


//
// instantiate the unit under test
//
AXIS_Deinterleaver uut 
(
  .aclk(aclk), 
  .aresetn(aresetn), 
  .deinterleave(deinterleave),
  .enabled(enabled),
  .s_axis_tdata(s_axis_tdata),
  .s_axis_tvalid(s_axis_tvalid),
  .s_axis_tready(s_axis_tready),
  .m00_axis_tdata(m00_axis_tdata),
  .m00_axis_tvalid(m00_axis_tvalid),
  .m00_axis_tready(m00_axis_tready),
  .m01_axis_tdata(m01_axis_tdata),
  .m01_axis_tvalid(m01_axis_tvalid),
  .m01_axis_tready(m01_axis_tready)
);

parameter CLK_PERIOD=10;              // 100MHz
// Generate the clock : 100 MHz    
always #(CLK_PERIOD/2) aclk = ~aclk;

  initial begin
    aresetn=0;
    deinterleave=0;
    enabled=0;

    @(posedge aclk)
    @(posedge aclk)
    #2
    enabled=1;
    aresetn=1;

    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    #2
    m00_axis_tready = 1;
    m01_axis_tready = 1;

    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    #2                                    // 2ns delay  
    s_axis_tdata = 24'h500000;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
    #2
    s_axis_tdata = 24'h500001;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
    #2
    s_axis_tdata = 24'h500002;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
    #2
    s_axis_tdata = 24'h500003;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
    #2
    s_axis_tdata = 24'h500004;          // new data, assert valid
    s_axis_tvalid = 1;
    m00_axis_tready=0;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
    #2
    m00_axis_tready=1;
    s_axis_tdata = 24'h500005;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
    #2
    enabled = 0;
    s_axis_tdata = 24'h500006;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
    #2
    deinterleave = 1;
    s_axis_tdata = 24'h500007;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
    #2
    s_axis_tdata = 24'h500008;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
    #2
    enabled=1;
    s_axis_tdata = 24'h500009;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
    #2
    s_axis_tdata = 24'h50000a;          // new data, assert valid
    s_axis_tvalid = 1;
    m01_axis_tready=0;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)



    #2
    m01_axis_tready=1;
    s_axis_tdata = 24'h50000b;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)



    #2
    s_axis_tdata = 24'h50000c;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)



    #2
    s_axis_tdata = 24'h50000d;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)



    #2
    s_axis_tdata = 24'h50000e;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)



    #2
    s_axis_tdata = 24'h50000f;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)



    #2
    s_axis_tdata = 24'h500010;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)



    #2
    s_axis_tdata = 24'h500011;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
//    @(posedge aclk)                           // end can't follow these constructs!
//    @(posedge aclk)                           // don't know why!
//    @(posedge aclk)
//    @(posedge aclk)
//    @(posedge aclk)
    
  end
endmodule
