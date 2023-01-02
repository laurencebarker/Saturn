`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    22.07.2022 16:42:01
// Design Name:    RX DDC testbench
// Module Name:    rx_ddc_tb
// Project Name:   Saturn
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    Testbench for RX downconverter
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 


module rx_ddc_tb( );

//////////////////////////////////////////////////////////////////////////////////
// Test Bench Signals
//////////////////////////////////////////////////////////////////////////////////
// Clock and Reset
  reg aclk = 0;
  reg rstn = 0;

  reg Byteswap;
  reg[1:0] ChanConfig;
  reg [31:0] ChanFreq;
  reg [2:0] CicInterp;

  reg [31:0] LOIQIn_tdata;
  reg LOIQIn_tvalid = 0;
  wire LOIQIn_tready;
  reg [7:0]LOIQIn_tdest = 0;
  reg [7:0]LOIQIn_tid = 0;
  reg [0:0]LOIQIn_tkeep = 0;
  reg [0:0]LOIQIn_tuser = 0;
  reg LOIQIn_tlast = 0;

  wire [31:0] LOIQOut_tdata;
  wire LOIQOut_tvalid;

  reg LOIQSel;

  wire [47:0] M_AXIS_DATA_tdata;
  wire M_AXIS_DATA_tvalid;
  reg M_AXIS_DATA_tready;

  reg [15:0] adc1;
  reg [15:0] adc2;
  reg [15:0] tx_samples;
//  reg [15:0] test_source;
  wire [15:0] test_source;
  wire test_source_tvalid;


  wire [47:0]debug_tdata;
  wire debug_tvalid;

//
// testbed variables
//
  reg[23:0] IOut;
  reg[23:0] QOut;
  reg[23:0] IDebOut;
  reg[23:0] QDebOut;

  reg [31:0] fd_w;                   // file handle
  reg [31:0] SampleCount = 0; // sample counter for file write
  reg [31:0] RequiredSampleCount = 0;
  reg [31:0] DiscardSampleCount = 0;
  reg [31:0] DebugSampleCount = 0;

  DDC_Block UUT
  (
        .Byteswap(Byteswap),
        .ChanConfig(ChanConfig),
        .ChanFreq(ChanFreq),
        .CicInterp(CicInterp),
        .LOIQIn_tdata(LOIQIn_tdata),
        .LOIQIn_tdest(LOIQIn_tdest),
        .LOIQIn_tid(LOIQIn_tid),
        .LOIQIn_tkeep(LOIQIn_tkeep),
        .LOIQIn_tlast(LOIQIn_tlast),
        .LOIQIn_tready(LOIQIn_tready),
        .LOIQIn_tuser(LOIQIn_tuser),
        .LOIQIn_tvalid(LOIQIn_tvalid),
        .LOIQOut_tdata(LOIQOut_tdata),
        .LOIQOut_tvalid(LOIQOut_tvalid),
        .LOIQSel(LOIQSel),
        .M_AXIS_DATA_tdata(M_AXIS_DATA_tdata),
        .M_AXIS_DATA_tready(M_AXIS_DATA_tready),
        .M_AXIS_DATA_tvalid(M_AXIS_DATA_tvalid),
        .aclk(aclk),
        .adc1(adc1),
        .adc2(adc2),
        .rstn(rstn),
        .test_source(test_source),
        .tx_samples(tx_samples),
        .debug_tdata(debug_tdata),
        .debug_tvalid(debug_tvalid)
  );


  dds_compiler_0 siggen
  (
    .aclk               (aclk),
    .M_AXIS_DATA_tdata  (test_source),
    .M_AXIS_DATA_tvalid (test_source_tvalid)
  );



parameter CLK_PERIOD=8;              // 125MHz
// Generate the clock : 125 MHz    
always #(CLK_PERIOD/2) aclk = ~aclk;




//////////////////////////////////////////////////////////////////////////////////
// Main Process
//////////////////////////////////////////////////////////////////////////////////
//
initial begin
//
// open file for I/Q samples to be written to:
//
    DiscardSampleCount = 100;          // samples to be discarded before starting to record (filter initiailising)
    RequiredSampleCount = 1024;
    fd_w = $fopen("./ddcdata.txt", "w");
    if(fd_w) $display("file opened successfully");
    else $display("file open FAIL");
//    fd_debw = $fopen("./ddcdebdata.txt", "w");
//    if(fd_debw) $display("debug file opened successfully");
//    else $display("debug file open FAIL");
    
    //Assert the reset
    Byteswap = 0;
    ChanConfig = 2;                 // select test DDS in (2MHz)
//    ChanConfig = 0;                 // select ADC1
    ChanFreq = 32'h03F55555;      // 1.9MHz
//    ChanFreq = 32'h00355555;      // 0.1MHz
    CicInterp = 6;				  // 1536KHz
    LOIQIn_tdata = 0;
    LOIQIn_tvalid = 0;
    LOIQSel = 0;
    M_AXIS_DATA_tready = 1;
    rstn = 0;
    adc1 = 16'h7FFF;
    adc2= 0;
    tx_samples = 0;

    #1000
    // Release the reset
    rstn = 1;
end



//
// collect I/Q output to a file, when valid data presented
//
always @(posedge aclk)
begin
    if(M_AXIS_DATA_tvalid == 1)
//    if(debug_tvalid == 1)
    begin
        IOut = M_AXIS_DATA_tdata[23:0];
        QOut = M_AXIS_DATA_tdata[47:24];
//        IDebOut = debug_tdata[23:0];
//        QDebOut = debug_tdata[47:24];
        SampleCount = SampleCount + 1;
        if(SampleCount > DiscardSampleCount)
            $fwrite(fd_w, "%d,%d\n", $signed(IOut), $signed(QOut));
        $display("Samples collected = %d\n",SampleCount);
        if(SampleCount == (RequiredSampleCount + DiscardSampleCount))
        begin
            $fclose(fd_w);
            $finish;
        end
    end
end


endmodule