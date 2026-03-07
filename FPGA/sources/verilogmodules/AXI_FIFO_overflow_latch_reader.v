
`timescale 1 ns / 1 ps
//////////////////////////////////////////////////////////////////////////////////
// Company: HPSDR
// Engineer: Laurence Barker G8NJJ
// 
// Create Date: 17.05.2021 10:24:28
// Design Name: 
// Module Name: AXI_FIFO_overflow_reader
// Project Name: Saturn
// Target Devices: Artix 7
// Tool Versions: 
// Description: 
// latch FIFO overflow indications and hold until read.
// also used for FIFO overflows.
// function added: also record ADC peak samples within the same period as ADC overflows
// AXI4-lite bus interface to read back the overflow indications and clear the latch.
//
// Registers:
//  addr 0         Overflow register (read only, with side effect)
//                 bit 0: reads out latched overflow 1
//                 bit 1: reads out latched overflow 2
//                 bit 15: reads out latched overflow 16
//	An axi4 read transaction clears the latch.
//  on read: the ADC peak values are latched, read yto be read out.
// ** it is critical to read the Overflow register first **
//
// addr 4          ADC1 peak amplitude value (16 bit unsigned)
// addr 8          ADC2 peak amplitude value (16 bit unsigned)
// addr C          ADC2 peak amplitude value (16 bit unsigned)


//
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: 
// 
//////////////////////////////////////////////////////////////////////////////////

module AXI_FIFO_overflow_reader #
(
  parameter integer AXI_DATA_WIDTH = 32,
  parameter integer AXI_ADDR_WIDTH = 16
)
(
  // System signals
  input  wire                      aclk,
  input  wire                      aresetn,

  // AXI bus Slave 
  input  wire [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,  // AXI4-Lite slave: Write address
  input  wire                      s_axi_awvalid, // AXI4-Lite slave: Write address valid
  output wire                      s_axi_awready, // AXI4-Lite slave: Write address ready
  input  wire [AXI_DATA_WIDTH-1:0] s_axi_wdata,   // AXI4-Lite slave: Write data
  input  wire                      s_axi_wvalid,  // AXI4-Lite slave: Write data valid
  output wire                      s_axi_wready,  // AXI4-Lite slave: Write data ready
  output wire [1:0]                s_axi_bresp,   // AXI4-Lite slave: Write response
  output wire                      s_axi_bvalid,  // AXI4-Lite slave: Write response valid
  input  wire                      s_axi_bready,  // AXI4-Lite slave: Write response ready
  input  wire [AXI_ADDR_WIDTH-1:0] s_axi_araddr,  // AXI4-Lite slave: Read address
  input  wire                      s_axi_arvalid, // AXI4-Lite slave: Read address valid
  output wire                      s_axi_arready, // AXI4-Lite slave: Read address ready
  output wire [AXI_DATA_WIDTH-1:0] s_axi_rdata,   // AXI4-Lite slave: Read data
  output wire [1:0]                s_axi_rresp,   // AXI4-Lite slave: Read data response
  output wire                      s_axi_rvalid,  // AXI4-Lite slave: Read data valid
  input  wire                      s_axi_rready,  // AXI4-Lite slave: Read data ready


// FIFO overflow signals
    input wire overflow1,				// FIFO1 overflow input
    input wire overflow2,				// FIFO2 overflow input
    input wire overflow3,				// FIFO3 overflow input
    input wire overflow4,				// FIFO4 overflow input
    input wire overflow5,				// FIFO5 overflow input
    input wire overflow6,				// FIFO6 overflow input
    input wire overflow7,				// FIFO7 overflow input
    input wire overflow8,				// FIFO8 overflow input
    input wire overflow9,				// FIFO9 overflow input
    input wire overflow10,				// FIFO10 overflow input
    input wire overflow11,				// FIFO11 overflow input
    input wire overflow12,				// FIFO12 overflow input
    input wire overflow13,				// FIFO13 overflow input
    input wire overflow14,				// FIFO14 overflow input
    input wire overflow15,				// FIFO15 overflow input
    input wire overflow16,				// FIFO16 overflow input
    
// ADC input data for ADC max sample value detection
    input wire [15:0] ADC1data,
    input wire [15:0] ADC2data
);

  reg [AXI_DATA_WIDTH-1:0] raddrreg;
  reg [AXI_DATA_WIDTH-1:0] rdatareg;
  reg [AXI_DATA_WIDTH-1:0] overflowdatareg;
  reg [AXI_DATA_WIDTH-1:0] overflowdataregpl1;      // pipelined once
  reg [AXI_DATA_WIDTH-1:0] overflowdataregpl2;      // pipelined twice
  reg signed [15:0]        ADC1datareg;
  reg signed [15:0]        ADC2datareg;
  reg signed [15:0]        ADC1magnitudereg;
  reg signed [15:0]        ADC2magnitudereg;
  reg [AXI_DATA_WIDTH-1:0] ADC1latchedpeakreg;
  reg [AXI_DATA_WIDTH-1:0] ADC2latchedpeakreg;
  reg [AXI_DATA_WIDTH-1:0] ADC1currentpeakreg;
  reg [AXI_DATA_WIDTH-1:0] ADC2currentpeakreg;
  reg arreadyreg;                           // false when write address has been latched
  reg rvalidreg;                            // true when read data out is valid

//
// AXI read strategy:
// 1. at reset, assert arready and tready, to be able to accept address and stream transfers 
// 1a. latch the overrrange bits when they occur
// 2. when arvalid is true, signalling address transfer, deassert arready 
// 3. assert rvalid when arvalid is false
// 4. when rvalid and rready both true, data is transferred:
// 4a. clear the data;
// 4b. deassert rvalid
// 4c. reassert arready
// it is a requirement that there is no combinatorial path from inpu tot output
//


  assign s_axi_rdata = rdatareg;
  assign s_axi_arready = arreadyreg;
  assign s_axi_rvalid = rvalidreg;
  assign s_axi_rresp = 2'd0;
//
// and outputs to make sure we don't respond to a write
//
  assign s_axi_bresp = 2'd0;                         // no response to write access
  assign s_axi_awready = 1'b0;                       // no response to write access
  assign s_axi_wready = 1'b0;                        // no response to write access
  assign s_axi_bvalid = 1'b0;                        // no response to write access



  always @(posedge aclk)
  begin
    if(~aresetn)
    begin
// step 1
      raddrreg <= {(AXI_DATA_WIDTH){1'b0}};
      rdatareg <= {(AXI_DATA_WIDTH){1'b0}};

      overflowdatareg <= {(AXI_DATA_WIDTH){1'b0}};
      ADC1datareg <= 0;
      ADC2datareg <= 0;
      ADC1magnitudereg <= 0;
      ADC2magnitudereg <= 0;
      ADC1latchedpeakreg <= {(AXI_DATA_WIDTH){1'b0}};
      ADC2latchedpeakreg <= {(AXI_DATA_WIDTH){1'b0}};
      ADC1currentpeakreg <=0;
      ADC2currentpeakreg <= 0;
      arreadyreg <= 1'b1;                           // ready for address transfer
      rvalidreg <= 1'b0;                            // not ready to transfer read data
    end
    else
    begin
// step 1b. latch the overflow bits
      if(overflow1)
        overflowdatareg[0] <= 1'b1;            // latch data
      if(overflow2)
        overflowdatareg[1] <= 1'b1;            // latch data
      if(overflow3)
        overflowdatareg[2] <= 1'b1;            // latch data
      if(overflow4)
        overflowdatareg[3] <= 1'b1;            // latch data
      if(overflow5)
        overflowdatareg[4] <= 1'b1;            // latch data
      if(overflow6)
        overflowdatareg[5] <= 1'b1;            // latch data
      if(overflow7)
        overflowdatareg[6] <= 1'b1;            // latch data
      if(overflow8)
        overflowdatareg[7] <= 1'b1;            // latch data
      if(overflow9)
        overflowdatareg[8] <= 1'b1;            // latch data
      if(overflow10)
        overflowdatareg[9] <= 1'b1;            // latch data
      if(overflow11)
        overflowdatareg[10] <= 1'b1;           // latch data
      if(overflow12)
        overflowdatareg[11] <= 1'b1;           // latch data
      if(overflow13)
        overflowdatareg[12] <= 1'b1;           // latch data
      if(overflow14)
        overflowdatareg[13] <= 1'b1;           // latch data
      if(overflow15)
        overflowdatareg[14] <= 1'b1;           // latch data
      if(overflow16)
        overflowdatareg[15] <= 1'b1;           // latch data
// latch input ADC data
      ADC1datareg <= ADC1data;
      ADC2datareg <= ADC2data;
//
// step 1c. process ADC data to find peaks
// this is pipelined into two cycles. Find magnitude; thern running max magnitude. 
// find
      if(ADC1datareg < 0)
        ADC1magnitudereg <= -ADC1datareg;
      else
        ADC1magnitudereg <= ADC1datareg;
      if(ADC1magnitudereg > ADC1currentpeakreg)
        ADC1currentpeakreg <= ADC1magnitudereg;

      if(ADC2datareg < 0)
        ADC2magnitudereg <= -ADC2datareg;
      else
        ADC2magnitudereg <= ADC2datareg;
      if(ADC2magnitudereg > ADC2currentpeakreg)
        ADC2currentpeakreg <= ADC2magnitudereg;

//
// step 1d. Register overflow bits to same pipeline depth
//
    overflowdataregpl1 <= overflowdatareg;
    overflowdataregpl2 <= overflowdataregpl1;
    

// step 2. read address transaction: latch address when arvalid and arready both true
//         and deassert arready as the addres transaction is in its last cycle    
      if(s_axi_arvalid & arreadyreg)
      begin
        arreadyreg <= 1'b0;                     // clear when address transaction happens
        raddrreg <= s_axi_araddr;               // latch the required read address
      end

// step 3. assert rvalid when address and stream data transfers are ready
      if(!arreadyreg)                           // address complete and stream already complete
      begin
        rvalidreg <= 1'b1;                                  // signal ready to complete data
        case (raddrreg[3:2])
            0: rdatareg <= overflowdataregpl2;
            1: rdatareg <= ADC1latchedpeakreg;
            2: rdatareg <= ADC2latchedpeakreg;
            3: rdatareg <= ADC2latchedpeakreg;
            
        endcase
      end

// step 4. When rvalid and rready, terminate the transaction & clear data.
      if(rvalidreg & s_axi_rready)
      begin
        rvalidreg <= 1'b0;                                  // deassert rvalid
        arreadyreg <= 1'b1;                                 // ready for new address
        overflowdatareg <= {(AXI_DATA_WIDTH){1'b0}};
        if(raddrreg[3:2] == 0)                              // store peaks if it is the overflow register being read
        begin
          ADC1latchedpeakreg <= ADC1currentpeakreg;
          ADC2latchedpeakreg <= ADC2currentpeakreg;
          ADC1currentpeakreg <= 0;
          ADC2currentpeakreg <= 0;
        end
      end
    end
  end



endmodule
