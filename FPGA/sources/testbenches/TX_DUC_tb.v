`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    22.07.2022 16:42:01
// Design Name:    TX DUC testbench
// Module Name:    tx_duc_tb
// Project Name:   Saturn
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    Testbench for TX upconverter
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 


module tx_duc_tb( );

//////////////////////////////////////////////////////////////////////////////////
// Test Bench Signals
//////////////////////////////////////////////////////////////////////////////////
// Clock and Reset
reg clk122 = 0;
reg resetn1;
reg [47:0]S_AXIS_tdata;
wire S_AXIS_tready;
reg S_AXIS_tvalid;
reg[31:0]TXConfig;
wire [15:0]TXDACData;
reg [31:0]TXLOTune;
wire [15:0]TXSamplesToRX;
reg [15:0]cic_rate;
reg sel;



TX_DUC UUT
(
    .S_AXIS_tdata(S_AXIS_tdata),
    .S_AXIS_tready(S_AXIS_tready),
    .S_AXIS_tvalid(S_AXIS_tvalid),
    .TXConfig(TXConfig),
    .TXDACData(TXDACData),
    .TXLOTune(TXLOTune),
    .TXSamplesToRX(TXSamplesToRX),
    .cic_rate(cic_rate),
    .clk122(clk122),
    .resetn1(resetn1),
    .sel(sel)
);

parameter CLK_PERIOD=8;              // 125MHz
// Generate the clock : 125 MHz    
always #(CLK_PERIOD/2) clk122 = ~clk122;




//////////////////////////////////////////////////////////////////////////////////
// Main Process
//////////////////////////////////////////////////////////////////////////////////
//
initial begin
    //Assert the reset
    resetn1 = 0;
    S_AXIS_tdata = 47'h0000007FFFFF;                // 1, 0
    S_AXIS_tvalid = 1;
    TXConfig = 32'h801FFFF8;                        // half of full scale amplitude
    TXLOTune = 32'h03F55555;                        // 1.9MHz
    cic_rate = 16'h80;
    sel = 1;                                        // select data out
    #1000
    // Release the reset
    resetn1 = 1;
end



endmodule