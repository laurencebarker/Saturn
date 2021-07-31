//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    15.07.2021 17:18:01
// Design Name:    axis_multiplier_tb.v
// Module Name:    axis_multiplier_tb
// Project Name:   Saturn 
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    testbench for axi stream multiplier
//
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: 
// 
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps
  
module axis_multiplier_tb();
  
////////////////////////////////////////////////////////////////////////////////// 
// axi stream multiplier Test Bench Signals
// use wire to connect a module output
// use reg to connect a module input
//////////////////////////////////////////////////////////////////////////////////  
  reg aclk=0;
  reg aresetn=1;

  reg [15:0] s00_axis_tdata;      // input A stream
  reg        s00_axis_tvalid;
  wire       s00_axis_tready; 

  reg [15:0] s01_axis_tdata;      // input B stream
  reg        s01_axis_tvalid;
  wire       s01_axis_tready; 
  
  // AXI stream master outputs
  wire [15:0] m_axis_tdata;      // output A * B stream
  wire        m_axis_tvalid;
  reg         m_axis_tready; 


//
// instantiate the unit under test
//
axis_multiplier uut 
(
  .aclk(aclk), 
  .aresetn(aresetn), 
  .s00_axis_tdata(s00_axis_tdata),
  .s00_axis_tvalid(s00_axis_tvalid),
  .s00_axis_tready(s00_axis_tready),
  .s01_axis_tdata(s01_axis_tdata),
  .s01_axis_tvalid(s01_axis_tvalid),
  .s01_axis_tready(s01_axis_tready),
  .m_axis_tdata(m_axis_tdata),
  .m_axis_tvalid(m_axis_tvalid),
  .m_axis_tready(m_axis_tready)
);

parameter CLK_PERIOD=100;              // 10MHz
// Generate the clock : 10 MHz    
always #(CLK_PERIOD/2) aclk = ~aclk;

  initial begin
    aresetn=0;
    m_axis_tready = 0;
    s00_axis_tvalid = 0;		// set neither tvalid
    s01_axis_tvalid = 0;
    s00_axis_tdata = 0;          	// clear data
    s01_axis_tdata = 0;

    @(posedge aclk)
    @(posedge aclk)
    #20
    aresetn=1;

    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    #20
    m_axis_tready = 1;
    s00_axis_tvalid = 0;		// set neither tvalid
    s01_axis_tvalid = 0;
    s00_axis_tdata = 1001;          	// new data, assert valid
    s01_axis_tdata = 4;

    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    #20
    s00_axis_tvalid = 1;		// set A tvalid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    #20
    s01_axis_tvalid = 1;		// set B tvalid
    @(posedge aclk)
    #20
    s00_axis_tvalid = 0;		// set neither tvalid
    s01_axis_tvalid = 0;
    @(posedge aclk)
    @(posedge aclk)
//
// now test output throttling
//
    #20
    m_axis_tready = 0;
    s00_axis_tvalid = 1;		// new data, both valid
    s01_axis_tvalid = 1;
    s00_axis_tdata = 2003;          	// new data, assert valid
    s01_axis_tdata = 3;
    @(posedge aclk)
    #20
    s00_axis_tvalid = 0;		// set neither tvalid
    s01_axis_tvalid = 0;
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    #20
    m_axis_tready = 1;
    @(posedge aclk)
    @(posedge aclk)
    s00_axis_tvalid = 0;		// set neither tvalid
    s01_axis_tvalid = 0;

    
  end
endmodule
