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

wire [31:0] LR_Spkr_data_tdata;
reg LR_Spkr_data_tvalid;
wire LR_Spkr_data_tready;

reg [15:0] S_AXIS_KeyerAmpl_tdata;
reg S_AXIS_KeyerAmpl_tvalid;
wire S_AXIS_KeyerAmpl_tready;


//
// testbench signals
//
wire [31:0] DDS_tdata;
wire DDS_tvalid;
wire DDS_tready;


reg [15:0] SidetoneFreq;
reg [15:0] SidetoneVol;
reg[31:0]SampleCount = 0;
reg signed [15:0] Ramp = 0; 


audio_codec UUT
(
    .BCLK (BCLK),
    .Byteswap (Byteswap),
    .CodecConfig (CodecConfig),
    .LRCLK (LRCLK),
    .LR_Spkr_data_tdata (LR_Spkr_data_tdata),
    .LR_Spkr_data_tready (DDS_tready),
    .LR_Spkr_data_tvalid (DDS_tvalid),
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

dds_compiler_0 siggen
(
    .aclk (clk12),
    .aresetn(arstn),
    .M_AXIS_DATA_tdata(DDS_tdata),
    .M_AXIS_DATA_tvalid(DDS_tvalid),
    .M_AXIS_DATA_tready(DDS_tready)
);


parameter CLK_PERIOD=81.380208;              // 12.288MHz
// Generate the clock : 12.288 MHz    
always #(CLK_PERIOD/2) clk12 = ~clk12;

//
// make a smaller than 16+16 bits speaker data drive signal:
// take 12 bits of data from each 16, sign extended
//
assign LR_Spkr_data_tdata[31:0] = 
{
DDS_tdata[31], DDS_tdata[31], DDS_tdata[31], DDS_tdata[31], 
DDS_tdata[31:20],
DDS_tdata[15], DDS_tdata[15], DDS_tdata[15], DDS_tdata[15],
DDS_tdata[15:4]    
};


//////////////////////////////////////////////////////////////////////////////////
// Main Process
//////////////////////////////////////////////////////////////////////////////////
//
initial begin
    //Assert the reset
    arstn = 0;
    i2srxd = 0;
    Byteswap = 0;

    SidetoneVol = 32000;					// half amplitude
    SidetoneFreq = 682;						// 500Hz
    CodecConfig = (SidetoneVol << 16) | SidetoneFreq;
 
//
// speaker data and keyer ramp are throttled by tready, so tvalid can be left at 1
//
    RX_Audio_data_tready = 1;
    //LR_Spkr_data_tdata = 0;
    LR_Spkr_data_tvalid = 1;
    S_AXIS_KeyerAmpl_tdata = 0;
    S_AXIS_KeyerAmpl_tvalid = 1;

    #1000
    // Release the reset
    arstn = 1;
end

//
// generate ramp
// t=100ms (4800 samples): start ramp
// t=200ms (9600 samples) stop ramp at near full ampl
// t=500ms (24000 samples) start ramp down
// t=600ms (28800 samples) stop ramp down
//
always @(posedge clk12)
begin
    if((DDS_tready == 1) && (DDS_tvalid == 1))
    begin
        SampleCount = SampleCount+1;
        
        if((SampleCount > 4800) && (SampleCount < 9600))
            Ramp = Ramp + 6;
        else if((SampleCount > 24000) && (SampleCount < 28800))
            Ramp = Ramp - 6;
        S_AXIS_KeyerAmpl_tdata = Ramp;
    end
end



endmodule