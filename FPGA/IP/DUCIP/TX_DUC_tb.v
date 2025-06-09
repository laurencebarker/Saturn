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
  wire [31:0]testdata;

//
// debug data write variables
// (set required samples counts etc just afer "initial begin", not here)
//
  reg RecordDiskFile = 0;
  reg [31:0] fd_w;                          // file handle
  reg [31:0] SampleCount = 0;               // sample counter for file write
  reg [31:0] RequiredSampleCount = 0;       // sample size to collect
  reg [31:0] DiscardSampleCount = 0;        // start sample (to allow initialise)


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
    .sel(sel),
    .testdata(testdata)
);

parameter CLK_PERIOD=8.1380208;              // 122.88MHz
// Generate the clock : 122.88 MHz    
always #(CLK_PERIOD/2) clk122 = ~clk122;




//////////////////////////////////////////////////////////////////////////////////
// Main Process
//////////////////////////////////////////////////////////////////////////////////
//
initial begin
//
// setup debug data recording parameters
//
    RecordDiskFile = 1;                 // enable file write
    DiscardSampleCount = 100000;        // samples to be discarded before starting to record (filter initialising)
    RequiredSampleCount = 262144;
    if(RecordDiskFile == 1)
    begin
        fd_w = $fopen("./ducoffbindata.txt", "w");
        if(fd_w) $display("file opened successfully");
        else $display("file open FAIL");
    end




//
// Assert the reset
//
    resetn1 = 0;
//    S_AXIS_tdata = 47'h0000007FFFFF;                // 1, 0
    S_AXIS_tdata = 47'h000000733332;                // 0.9, 0
    S_AXIS_tvalid = 1;
//    TXConfig = 32'h80033008;                        // nearly full scale amplitude - after adding cordic
//    TXConfig = 32'h80028008;                        // full scale amplitude, 23 bit DDS, complex mult
//    TXConfig = 32'h80020008;                        // full scale amplitude, 23 bit DDS, complex mult
    TXConfig = 32'h8002A008;                          // near full scale full scale amplitude, 23 bit DDS, complex mult
    cic_rate = 16'd80;
    sel = 1;                                        // select data out
//
// select DDS frequency
//
//    TXLOTune = 32'h03F55555;                        // 1.9MHz
//    TXLOTune = 32'h07EAAAAA;                        // 3.8MHz
    TXLOTune = 32'h0ECAAAAA;                        // 7.1MHz
//    TXLOTune = 32'h1D600000;                        // 14.1MHz
//    TXLOTune = 32'h2BF55555;                        // 21.1MHz
//    TXLOTune = 32'h3A8AAAAA;                        // 28.1MHz
//    TXLOTune = 32'h68600000;                        // 50.1MHz
//    TXLOTune = 32'h6B4AAAAA;                        // 51.5MHz
    #1000
    // Release the reset
    resetn1 = 1;
end


//
// collect I/Q output to a file, when valid data presented
// data available on every clock
//
always @(posedge clk122)
    if(RecordDiskFile == 1)
    begin
        SampleCount = SampleCount + 1;
        if(SampleCount > DiscardSampleCount)
//            $fwrite(fd_w, "%d\n", $signed(TXSamplesToRX));
//            $fwrite(fd_w, "%d\n", $signed(testdata));
        $fwrite(fd_w, "%d\n", $unsigned(TXDACData));        // offset binary DAC output
        $display("Sample number = %d\n",SampleCount);
        if(SampleCount == (RequiredSampleCount + DiscardSampleCount))
        begin
            $fclose(fd_w);
            $finish;
        end
    end



endmodule