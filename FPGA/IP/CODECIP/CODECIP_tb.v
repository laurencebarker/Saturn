`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    16.01.2023 
// Design Name:    CODEC IP testbench
// Module Name:    codec_ip_tb
// Project Name:   Saturn
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    Testbench for audio codec interface
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 


module codec_ip_tb( );

//////////////////////////////////////////////////////////////////////////////////
// Test Bench Signals
//////////////////////////////////////////////////////////////////////////////////
// Clock and Reset
reg clk12 = 0;
reg arstn;

// interface signals
wire BCLK;
wire LRCLK;
wire MCLK;
wire i2stxd;
reg i2srxd;

reg Byteswap;

reg [31:0] CodecConfig;

wire [15:0] RX_Audio_data_tdata;
wire RX_Audio_data_tvalid;
reg RX_Audio_data_tready;

reg [31:0] LR_Spkr_data_tdata;
reg LR_Spkr_data_tdata_tvalid;
wire LR_Spkr_data_tdata_tready;

reg [15:0] S_AXIS_KeyerAmpl_tdata;
reg S_AXIS_KeyerAmpl_tvalid;
wire S_AXIS_KeyerAmpl_tready;


reg [15:0] SidetoneFreq;
reg [15:0] SidetoneVol;




TX_DUC UUT
(
    .BCLK (BCLK),
    .Byteswap (Byteswap),
    .CodecConfig (CodecConfig),
    .LRCLK (LRCLK),
    .LR_Spkr_data_tdata (LR_Spkr_data_tdata),
    .LR_Spkr_data_tready (LR_Spkr_data_tready),
    .LR_Spkr_data_tvalid (LR_Spkr_data_tvalid),
    .MCLK (MCLK),
    .RX_Audio_Data_tdata (RX_Audio_Data_tdata),
    .RX_Audio_Data_tready (RX_Audio_Data_tready),
    .RX_Audio_Data_tvalid (RX_Audio_Data_tvalid),
    .S_AXIS_KeyerAmpl_tdata (S_AXIS_KeyerAmpl_tdata),
    .S_AXIS_KeyerAmpl_tready (S_AXIS_KeyerAmpl_tready),
    .S_AXIS_KeyerAmpl_tvalid (S_AXIS_KeyerAmpl_tvalid),
    .arstn (arstn),
    .clk12 (clk12),
    .i2srxd (i2srxd),
    .i2stxd (i2stxd)
);

parameter CLK_PERIOD=80;              // 12.5MHz
// Generate the clock : 12.5 MHz    
always #(CLK_PERIOD/2) clk12 = ~clk12;




//////////////////////////////////////////////////////////////////////////////////
// Main Process
//////////////////////////////////////////////////////////////////////////////////
//
initial begin
    //Assert the reset
    arstn = 0;
    i2srxd = 0;
    Byteswap = 0;

    SidetoneVol = 16383;					// half amplitude
    SidetoneFreq = 682;						// 500Hz
    CodecConfig = (SidetoneVol << 16) | SidetoneFreq;
 
//
// speaker data and keyer ramp are throttled by tready, so tvalid can be left at 1
//
    RX_Audio_data_tready = 1;
    LR_Spkr_data_tdata = 0;
    LR_Spkr_data_tvalid = 1;
    S_AXIS_KeyerAmpl_tdata = 0;
    S_AXIS_KeyerAmpl_tvalid = 1;

    #1000
    // Release the reset
    arstn = 1;
end



endmodule