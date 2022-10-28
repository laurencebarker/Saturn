`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    25/10/2022 16:42:01
// Design Name:    byte swap testbench
// Module Name:    byte_swap_testbench
// Project Name:   Saturn
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    Testbench for clock monitor
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 


module byte_swap16_tb( );

//////////////////////////////////////////////////////////////////////////////////
// Test Bench Signals
//////////////////////////////////////////////////////////////////////////////////
// Clock and Reset
reg aclk = 0;
reg aresetn = 1;
reg [15:0] s_axis_tdata = 0;
reg s_axis_tvalid = 0;
wire s_axis_tready;
wire [15:0] m_axis_tdata;
reg m_axis_tready = 0;
wire m_axis_tvalid;
reg swap = 0;

byteswap_16 UUT
(
    .aclk     (aclk),
    .aresetn  (aresetn),
    .swap     (swap),
    .s_axis_tdata (s_axis_tdata),
    .s_axis_tvalid (s_axis_tvalid),
    .s_axis_tready (s_axis_tready),
    .m_axis_tdata (m_axis_tdata),
    .m_axis_tvalid (m_axis_tvalid),
    .m_axis_tready (m_axis_tready)
);

parameter CLK_PERIOD=8.0;              // 125MHz
// Generate the clock : 125 MHz    
always #(CLK_PERIOD/2) aclk = ~aclk;


//////////////////////////////////////////////////////////////////////////////////
// Main Process
//////////////////////////////////////////////////////////////////////////////////
//
initial begin
    //Assert the reset
    aresetn = 0;
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    // Release the reset
    aresetn = 1;
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);

    #2
    s_axis_tvalid = 1;          // assert strobes
    m_axis_tready = 1;
    
    @ (posedge aclk);
    @ (posedge aclk);
    #2
    s_axis_tdata = 48'h0112;
    @ (posedge aclk);
    @ (posedge aclk);
    #2
    s_axis_tdata = 48'h0011;
    @ (posedge aclk);
    @ (posedge aclk);
    #2
    swap = 1;
    @ (posedge aclk);
    @ (posedge aclk);
    #2
    s_axis_tdata= 0;
    @ (posedge aclk);
    @ (posedge aclk);
    #2
    s_axis_tdata = 48'h0112;
    @ (posedge aclk);
    @ (posedge aclk);
    #2
    s_axis_tdata = 48'h0011;
    @ (posedge aclk);
    @ (posedge aclk);
end

endmodule