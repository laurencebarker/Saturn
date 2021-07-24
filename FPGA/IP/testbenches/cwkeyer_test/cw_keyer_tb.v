`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    23.07.2021 16:42:01
// Design Name:    CW keyer testbench
// Module Name:    Keyer_Testbench
// Project Name:   Saturn
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    Testbench for CW keyer
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 


module keyer_tb( );

//////////////////////////////////////////////////////////////////////////////////
// Test Bench Signals
//////////////////////////////////////////////////////////////////////////////////
// Clock and Reset
reg aclk = 0;
reg aresetn = 1;

reg [7:0] delay_time;
reg [9:0] hang_time;
reg key_down;
reg keyer_enable;
reg protocol_2;

wire CW_PTT;
wire [31:0] m_axis_tdata;
wire m_axis_tvalid;




keyer_block UUT
(
    .aclk            (aclk),
    .aresetn         (aresetn),
    .delay_time      (delay_time),
    .hang_time       (hang_time),
    .key_down        (key_down),
    .keyer_enable    (keyer_enable),
    .m_axis_tdata    (m_axis_tdata),
    .m_axis_tvalid   (m_axis_tvalid),
    .protocol_2      (protocol_2),
    .CW_PTT          (CW_PTT)

);

parameter CLK_PERIOD=8.1380208;              // 122.88MHz
// Generate the clock : 122.88 MHz    
always #(CLK_PERIOD/2) aclk = ~aclk;


//////////////////////////////////////////////////////////////////////////////////
// Main Process
//////////////////////////////////////////////////////////////////////////////////
//
initial begin
    //Assert the reset
    aresetn = 0;
    #340
    // Release the reset
    aresetn = 1;
end
initial begin    

hang_time = 10;
delay_time=3;
protocol_2=1;
keyer_enable=1;
//key down after 1us;
// key up after 20ms
#1000
key_down=1;
#20000000
key_down=0;

end
endmodule
