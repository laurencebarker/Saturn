//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    15.07.2021 17:18:01
// Design Name:    axi_stream_resizer_tb.v
// Module Name:    axi_stream_resizer_tb
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
  
module axi_stream_resizer_tb();
  
////////////////////////////////////////////////////////////////////////////////// 
// axi stream interleaver Test Bench Signals
// use wire to connect a module output
// use reg to connect a module input
//////////////////////////////////////////////////////////////////////////////////  
  reg aclk=0;
  reg aresetn=1;
  reg mux_reset;

  reg [47:0]  s_axis_tdata;      // input stream
  reg         s_axis_tvalid;
  wire        s_axis_tready; 

  // AXI stream master outputs
  wire [63:0] m_axis_tdata;      // output A stream
  wire        m_axis_tvalid;
  reg         m_axis_tready; 
      


//
// instantiate the unit under test
//
AXIS_Sizer_48to64 uut 
(
  .aclk(aclk), 
  .aresetn(aresetn), 
  .mux_reset(mux_reset),
  .s_axis_tdata(s_axis_tdata),
  .s_axis_tvalid(s_axis_tvalid),
  .s_axis_tready(s_axis_tready),
  .m_axis_tdata(m_axis_tdata),
  .m_axis_tvalid(m_axis_tvalid),
  .m_axis_tready(m_axis_tready)
);

parameter CLK_PERIOD=10;              // 100MHz
// Generate the clock : 100 MHz    
always #(CLK_PERIOD/2) aclk = ~aclk;

  initial begin
    aresetn=0;
    mux_reset=0;

    @(posedge aclk)
    @(posedge aclk)
    #2
    aresetn=1;

    @(posedge aclk)
    @(posedge aclk)
    #2
    m_axis_tready = 0;
    @(posedge aclk)
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'h000000000000;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)


// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'h111111111111;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'h222222222222;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'h333333333333;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    #2
    m_axis_tready = 1;
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'h444444444444;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'h555555555555;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'h666666666666;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'h777777777777;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'h888888888888;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'h999999999999;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'haaaaaaaaaaaa;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'hbbbbbbbbbbbb;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'hcccccccccccc;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'hdddddddddddd;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'heeeeeeeeeeee;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'hffffffffffff;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)




// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'h101010101010;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)


// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'h202020202020;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    #2
    mux_reset=1;                            // !!!!!!! asserts reset here
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay
    mux_reset=0;  
    s_axis_tdata = 48'h303030303030;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'h404040404040;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'h505050505050;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'h606060606060;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'h707070707070;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'h808080808080;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'h909090909090;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'ha0a0a0a0a0a0;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'hb0b0b0b0b0b0;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'hc0c0c0c0c0c0;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'hd0d0d0d0d0d0;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'he0e0e0e0e0e0;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'hf0f0f0f0f0f0;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    @(posedge aclk)
    
    
    
// input data beat    
    #2                                    // 2ns delay  
    s_axis_tdata = 48'h121212121212;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid

    
  end
endmodule
