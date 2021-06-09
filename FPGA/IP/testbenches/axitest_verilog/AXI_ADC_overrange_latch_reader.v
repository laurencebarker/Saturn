
`timescale 1 ns / 1 ps
//////////////////////////////////////////////////////////////////////////////////
// Company: HPSDR
// Engineer: Laurence Bsarker G8NJJ
// 
// Create Date: 17.05.2021 10:24:28
// Design Name: 
// Module Name: ADC_overrange_reader
// Project Name: Saturn
// Target Devices: Artix 7
// Tool Versions: 
// Description: 
// latch the LTC2208 ADC overrange indication and hold until read.
// AXI4-lite bus interface to read back the ADC overrange indications and clear the latch.
//
// Registers:
//  addr 0         Status register (read only, with side effect)
//                 bit 0: reads out latched overrange 1
//                 bit 2: reads out latched overrange 2
//		   An axi4 read transaction clears the latch.

//
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: 
// 
//////////////////////////////////////////////////////////////////////////////////

module AXI_ADC_overrange_reader #
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


// ADC overrange signals
    input wire overrange1,				// ADC1 overrange input
    input wire overrange2				// ADC2 overrange input
);

  reg [AXI_DATA_WIDTH-1:0] rdatareg;
  reg arreadyreg;                           // false when write address has been latched
  reg rvalidreg;                            // true when read data out is valid

//
// AXI read strategy:
// 1. at reset, assert arready and tready, to be able to accept address and stream transfers 
// 2. latch the overrrange bits when they occur
// 3. when arvalid is true, signalling address transfer, deassert arready 
// 4. assert rvalid when arvalid is false, and tready is false 
// 5. when rvalid and rready both true, data is transferred:
// 5a. clear the data;
// 5b. deassert rvalid
// 5c. reassert arready
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
      rdatareg <= {(AXI_DATA_WIDTH){1'b0}};
      arreadyreg <= 1'b1;                           // ready for address transfer
      rvalidreg <= 1'b0;                            // not ready to transfer read data
    end
    else
    begin
// step 2. latch the overrange bits
      if(overrange1)
        rdatareg[0] <= 1'b1;           // latch data
      if(overrange2)
        rdatareg[1] <= 1'b1;           // latch data

// step 3. read address transaction: latch when arvalid and arready both true    
      if(s_axi_arvalid & arreadyreg)
      begin
        arreadyreg <= 1'b0;                  // clear when address transaction happens
      end
// step 4. assert rvalid when address and stream data transfers are ready
      if(s_axi_arvalid & arreadyreg)       // address complete and stream already complete
      begin
        rvalidreg <= 1'b1;                                  // signal ready to complete data
      end
// step 5. When rvalid and rready, terminate the transaction & clear data.
      if(rvalidreg & s_axi_rready)
      begin
        rvalidreg <= 1'b0;                                  // deassert rvalid
        arreadyreg <= 1'b1;                                 // ready for new address
        rdatareg <= {(AXI_DATA_WIDTH){1'b0}};
      end
    end
  end



endmodule
