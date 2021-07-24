//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    15.07.2021 17:18:01
// Design Name:    axi_stream_interleaver_tb.v
// Module Name:    AXIS_Interleaver_tb
// Project Name:   Saturn 
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    testbench for axi stream interleaver 
//
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: 
// 
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps
  
module axi_stream_interleaver_tb();
  
////////////////////////////////////////////////////////////////////////////////// 
// axi stream interleaver Test Bench Signals
// use wire to connect a module output
// use reg to connect a module input
//////////////////////////////////////////////////////////////////////////////////  
  reg aclk=0;
  reg aresetn=1;
  reg interleave;
  reg enabled;

  reg [23:0] s00_axis_tdata;      // input A stream
  reg        s00_axis_tvalid;
  wire        s00_axis_tready; 

  reg [23:0] s01_axis_tdata;      // input B stream
  reg        s01_axis_tvalid;
  wire        s01_axis_tready; 
  
  // AXI stream master outputs
  wire [23:0] m00_axis_tdata;      // output A stream
  wire        m00_axis_tvalid;
  reg        m00_axis_tready; 

  wire [23:0] m01_axis_tdata;      // output B stream
  wire        m01_axis_tvalid;
  reg        m01_axis_tready; 
       
  // control signals
  wire mux_reset;                  // true when mux should be reset
  wire is_interleaved; 


//
// instantiate the unit under test
//
AXIS_Interleaver uut 
(
  .aclk(aclk), 
  .aresetn(aresetn), 
  .interleave(interleave),
  .enabled(enabled),
  .s00_axis_tdata(s00_axis_tdata),
  .s00_axis_tvalid(s00_axis_tvalid),
  .s00_axis_tready(s00_axis_tready),
  .s01_axis_tdata(s01_axis_tdata),
  .s01_axis_tvalid(s01_axis_tvalid),
  .s01_axis_tready(s01_axis_tready),
  .m00_axis_tdata(m00_axis_tdata),
  .m00_axis_tvalid(m00_axis_tvalid),
  .m00_axis_tready(m00_axis_tready),
  .m01_axis_tdata(m01_axis_tdata),
  .m01_axis_tvalid(m01_axis_tvalid),
  .m01_axis_tready(m01_axis_tready),
  .mux_reset(mux_reset),
  .is_interleaved(is_interleaved)
);

parameter CLK_PERIOD=10;              // 100MHz
// Generate the clock : 100 MHz    
always #(CLK_PERIOD/2) aclk = ~aclk;

  initial begin
    aresetn=0;
    interleave=0;
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
    s00_axis_tdata = 24'h500000;          // new data, assert valid
    s01_axis_tdata = 24'h500100;
    s00_axis_tvalid = 1;
    s01_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s00_axis_tvalid = 0;                        // deassert valid
    s01_axis_tvalid = 0;
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
    #2
    s00_axis_tdata = 24'h500001;          // new data, assert valid
    s01_axis_tdata = 24'h500101;
    s00_axis_tvalid = 1;
    s01_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s00_axis_tvalid = 0;                        // deassert valid
    s01_axis_tvalid = 0;
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
    #2
    s00_axis_tdata = 24'h500002;          // new data, assert valid
    s01_axis_tdata = 24'h500102;
    s00_axis_tvalid = 1;
    s01_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s00_axis_tvalid = 0;                        // deassert valid
    s01_axis_tvalid = 0;
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
    #2
    s00_axis_tdata = 24'h500003;          // new data, assert valid
    s01_axis_tdata = 24'h500103;
    s00_axis_tvalid = 1;
    s01_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s00_axis_tvalid = 0;                        // deassert valid
    s01_axis_tvalid = 0;
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
    #2
    s00_axis_tdata = 24'h500004;          // new data, assert valid
    s01_axis_tdata = 24'h500104;
    s00_axis_tvalid = 1;
    s01_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s00_axis_tvalid = 0;                        // deassert valid
    s01_axis_tvalid = 0;
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
    #2
    s00_axis_tdata = 24'h500005;          // new data, assert valid
    s01_axis_tdata = 24'h500105;
    s00_axis_tvalid = 1;
    s01_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s00_axis_tvalid = 0;                        // deassert valid
    s01_axis_tvalid = 0;
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
    #2
    enabled = 0;
    s00_axis_tdata = 24'h500006;          // new data, assert valid
    s01_axis_tdata = 24'h500106;
    s00_axis_tvalid = 1;
    s01_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s00_axis_tvalid = 0;                        // deassert valid
    s01_axis_tvalid = 0;
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
    #2
    interleave = 1;
    s00_axis_tdata = 24'h500007;          // new data, assert valid
    s01_axis_tdata = 24'h500107;
    s00_axis_tvalid = 1;
    s01_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s00_axis_tvalid = 0;                        // deassert valid
    s01_axis_tvalid = 0;
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
    #2
    s00_axis_tdata = 24'h500008;          // new data, assert valid
    s01_axis_tdata = 24'h500108;
    s00_axis_tvalid = 1;
    s01_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s00_axis_tvalid = 0;                        // deassert valid
    s01_axis_tvalid = 0;
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
    #2
    enabled=1;
    s00_axis_tdata = 24'h500009;          // new data, assert valid
    s01_axis_tdata = 24'h500109;
    s00_axis_tvalid = 1;
    s01_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s00_axis_tvalid = 0;                        // deassert valid
    s01_axis_tvalid = 0;
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
    #2
    s00_axis_tdata = 24'h50000a;          // new data, assert valid
    s01_axis_tdata = 24'h50010a;
    s00_axis_tvalid = 1;
    s01_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s00_axis_tvalid = 0;                        // deassert valid
    s01_axis_tvalid = 0;
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)



    #2
    s00_axis_tdata = 24'h50000b;          // new data, assert valid
    s01_axis_tdata = 24'h50010b;
    s00_axis_tvalid = 1;
    s01_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s00_axis_tvalid = 0;                        // deassert valid
    s01_axis_tvalid = 0;
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)



    #2
    s00_axis_tdata = 24'h50000c;          // new data, assert valid
    s01_axis_tdata = 24'h50010c;
    s00_axis_tvalid = 1;
    s01_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s00_axis_tvalid = 0;                        // deassert valid
    s01_axis_tvalid = 0;
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)



    #2
    s00_axis_tdata = 24'h50000d;          // new data, assert valid
    s01_axis_tdata = 24'h50010d;
    s00_axis_tvalid = 1;
    s01_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s00_axis_tvalid = 0;                        // deassert valid
    s01_axis_tvalid = 0;
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)



    #2
    s00_axis_tdata = 24'h50000e;          // new data, assert valid
    s01_axis_tdata = 24'h50010e;
    s00_axis_tvalid = 1;
    s01_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s00_axis_tvalid = 0;                        // deassert valid
    s01_axis_tvalid = 0;
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)



    #2
    s00_axis_tdata = 24'h50000f;          // new data, assert valid
    s01_axis_tdata = 24'h50010f;
    s00_axis_tvalid = 1;
    s01_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s00_axis_tvalid = 0;                        // deassert valid
    s01_axis_tvalid = 0;
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)



    #2
    s00_axis_tdata = 24'h500010;          // new data, assert valid
    s01_axis_tdata = 24'h500110;
    s00_axis_tvalid = 1;
    s01_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s00_axis_tvalid = 0;                        // deassert valid
    s01_axis_tvalid = 0;
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)



    #2
    s00_axis_tdata = 24'h500011;          // new data, assert valid
    s01_axis_tdata = 24'h500111;
    s00_axis_tvalid = 1;
    s01_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s00_axis_tvalid = 0;                        // deassert valid
    s01_axis_tvalid = 0;
//    @(posedge aclk)                           // end can't follow these constructs!
//    @(posedge aclk)                           // don't know why!
//    @(posedge aclk)
//    @(posedge aclk)
//    @(posedge aclk)
    
  end
endmodule
