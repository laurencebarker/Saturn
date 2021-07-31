//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    15.07.2021 17:18:01
// Design Name:    axi_stream_resizer_64_to_48_tb.v
// Module Name:    axi_stream_resizer_64to48_tb
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
  
module axi_stream_resizer_64to48_tb();
  
////////////////////////////////////////////////////////////////////////////////// 
// axi stream interleaver Test Bench Signals
// use wire to connect a module output
// use reg to connect a module input
//////////////////////////////////////////////////////////////////////////////////  
  reg aclk=0;
  reg aresetn=1;
  reg mux_reset;

  reg [63:0]  s_axis_tdata;      // input stream
  reg         s_axis_tvalid;
  wire        s_axis_tready; 

  // AXI stream master outputs
  wire [47:0] m_axis_tdata;      // output A stream
  wire        m_axis_tvalid;
  reg         m_axis_tready; 
      


//
// instantiate the unit under test
//
AXIS_Sizer_64to48 uut 
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
    m_axis_tready = 0;
    s_axis_tdata = 0;
    s_axis_tvalid = 0;

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
    s_axis_tdata = 64'h0000000000000000;          // new data, assert valid
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
    s_axis_tdata = 64'h1111111111111111;          // new data, assert valid
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
    s_axis_tdata = 64'h2222222222222222;          // new data, assert valid
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
    s_axis_tdata = 64'h3333333333333333;          // new data, assert valid
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
    s_axis_tdata = 64'h4444444444444444;          // new data, assert valid
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
    s_axis_tdata = 64'h5555555555555555;          // new data, assert valid
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
    s_axis_tdata = 64'h6666666666666666;          // new data, assert valid
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
    s_axis_tdata = 64'h7777777777777777;          // new data, assert valid
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
    s_axis_tdata = 64'h8888888888888888;          // new data, assert valid
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
    s_axis_tdata = 64'h9999999999999999;          // new data, assert valid
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
    s_axis_tdata = 64'haaaaaaaaaaaaaaaa;          // new data, assert valid
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
    s_axis_tdata = 64'hbbbbbbbbbbbbbbbb;          // new data, assert valid
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
    s_axis_tdata = 64'hcccccccccccccccc;          // new data, assert valid
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
    s_axis_tdata = 64'hdddddddddddddddd;          // new data, assert valid
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
    s_axis_tdata = 64'heeeeeeeeeeeeeeee;          // new data, assert valid
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
    s_axis_tdata = 64'hffffffffffffffff;          // new data, assert valid
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
    s_axis_tdata = 64'h1010101010101010;          // new data, assert valid
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
    s_axis_tdata = 64'h2020202020202020;          // new data, assert valid
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
    s_axis_tdata = 64'h3030303030303030;          // new data, assert valid
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
    s_axis_tdata = 64'h4040404040404040;          // new data, assert valid
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
    s_axis_tdata = 64'h5050505050505050;          // new data, assert valid
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
    s_axis_tdata = 64'h6060606060606060;          // new data, assert valid
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
    s_axis_tdata = 64'h7070707070707070;          // new data, assert valid
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
    s_axis_tdata = 64'h8080808080808080;          // new data, assert valid
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
    s_axis_tdata = 64'h9090909090909090;          // new data, assert valid
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
    s_axis_tdata = 64'ha0a0a0a0a0a0a0a0;          // new data, assert valid
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
    s_axis_tdata = 64'hb0b0b0b0b0b0b0b0;          // new data, assert valid
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
    s_axis_tdata = 64'hc0c0c0c0c0c0c0c0;          // new data, assert valid
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
    s_axis_tdata = 64'hd0d0d0d0d0d0d0d0;          // new data, assert valid
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
    s_axis_tdata = 64'he0e0e0e0e0e0e0e0;          // new data, assert valid
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
    s_axis_tdata = 64'hf0f0f0f0f0f0f0f0;          // new data, assert valid
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
    s_axis_tdata = 64'h1212121212121212;          // new data, assert valid
    s_axis_tvalid = 1;
    @(posedge aclk)
    #2
    s_axis_tvalid = 0;                        // deassert valid

    
  end
endmodule
