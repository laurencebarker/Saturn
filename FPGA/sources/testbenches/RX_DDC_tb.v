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

reg [31:0] ChanFreq;
reg[1:0] ChanConfig;
reg [15:0] adc1;
reg [15:0] adc2;
reg [15:0] test_source;
reg [15:0] tx_samples;

reg [31:0] LOIQIn_tdata;
reg LOIQIn_tvalid;
wire LOIQIn_tready;

reg LOIQSel;
reg Byteswap;
reg [2:0] CicInterp;

wire [31:0] LOIQOut_tdata;
wire LOIQOut_tvalid;

wire [47:0] M_AXIS_DATA_tdata;
wire M_AXIS_DATA_tvalid;
reg M_AXIS_DATA_tready;

reg[23:0] IOut;
reg[23:0] QOut;

reg [31:0] fd_w;                   // file handle
reg [31:0] SampleCount = 0; // sample counter for file write
reg [31:0] RequiredSampleCount = 0;

  DDC_Block UUT
 	(
	  .Byteswap(Byteswap),
        .ChanConfig(ChanConfig),
        .ChanFreq(ChanFreq),
        .CicInterp(CicInterp),
        .LOIQIn_tdata(LOIQIn_tdata),
        .LOIQIn_tdest({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .LOIQIn_tid({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .LOIQIn_tkeep(1'b1),
        .LOIQIn_tlast(1'b0),
        .LOIQIn_tuser(1'b0),
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
        .tx_samples(tx_samples)
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
    RequiredSampleCount = 8300;
    fd_w = $fopen("./ddcdata.txt", "w");
    if(fd_w) $display("file opened successfully");
    else $display("file open FAIL");
    
    //Assert the reset
    Byteswap = 0;
    ChanConfig = 0;
    ChanFreq = 32'h00355555;      // 100KHz
    CicInterp = 6;				  // 1536KHz
    LOIQIn_tdata = 0;
    LOIQIn_tvalid = 0;
    LOIQSel = 0;
    M_AXIS_DATA_tready = 1;
    rstn = 0;
    adc1 = 16'h7FFF;
    adc2= 0;
    tx_samples = 0;
    test_source = 0;

    #1000
    // Release the reset
    rstn = 1;
end


always @(posedge aclk)
begin
    if(M_AXIS_DATA_tvalid == 1)
    begin
    IOut = M_AXIS_DATA_tdata[23:0];
    QOut = M_AXIS_DATA_tdata[47:24];
    $fwrite(fd_w, "%d,%d\n", $signed(IOut), $signed(QOut));
    SampleCount = SampleCount + 1;
    $display("Samples collected = %d\n",SampleCount);
    if(SampleCount == RequiredSampleCount)
    begin
        $fclose(fd_w);
        $finish;
    end
    end
end


endmodule