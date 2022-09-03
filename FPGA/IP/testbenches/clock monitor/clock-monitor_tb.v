`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    22.07.2022 16:42:01
// Design Name:    clock monitor testbench
// Module Name:    clock_monitor_testbench
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


module clock_monitor_tb( );

//////////////////////////////////////////////////////////////////////////////////
// Test Bench Signals
//////////////////////////////////////////////////////////////////////////////////
// Clock and Reset
reg aclk = 0;
reg aresetn = 1;

reg ck0 = 0;
reg ck1 = 0;
reg ck2 = 0;
reg ck3 = 0;
wire [3:0] dout;
wire LED;


clock_monitor UUT
(
    .aclk     (aclk),
    .aresetn  (aresetn),
    .ck0      (ck0),
    .ck1      (ck1),
    .ck2      (ck2),
    .ck3      (ck3),
    .dout     (dout),
    .LED      (LED)

);

parameter CLK_PERIOD=8.0;              // 125MHz
// Generate the clock : 125 MHz    
always #(CLK_PERIOD/2) aclk = ~aclk;

parameter CLK0_PERIOD=8.1380208;              // 122.88MHz
// Generate the clock : 122.88 MHz    
always #(CLK0_PERIOD/2) ck0 = ~ck0;

parameter CLK1_PERIOD=100.0;              // 10MHz
// Generate the clock : 10 MHz    
always #(CLK1_PERIOD/2) ck1 = ~ck1;

parameter CLK2_PERIOD=8.1380208;              // 122.88MHz
// Generate the clock : 122.88 MHz    
always #(CLK2_PERIOD/2) ck2 = ~ck2;

parameter CLK3_PERIOD=8.1380208;              // 122.88MHz
// Generate the clock : 122.88 MHz    
always #(CLK3_PERIOD/2) ck3 = ~ck3;



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



endmodule