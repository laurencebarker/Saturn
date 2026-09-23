//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    15.03.2021 17:18:01
// Design Name:    axil_read64_reg.v
// Module Name:    AXIL_ReadReg_64
// Project Name:   Saturn 
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    Module to provide 64 bit readable register from axi4-lite bus
//                 AXI4-Lite bus interface to processor 
// Registers:
// note this is true even if the axi-lite bus is wider!
//  addr 0         read data [31:0]
//  addr 4         read data [63:32]
//  writes are acknowledged (OKAY) and ignored

// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: 
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1 ns / 1 ps

module AXIL_ReadReg_64 #
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

  input wire [AXI_DATA_WIDTH-1:0]  readdata0,
  input wire [AXI_DATA_WIDTH-1:0]  readdata1
);


  reg [AXI_ADDR_WIDTH-1:0] raddrreg;        // AXI read address register
  reg [AXI_DATA_WIDTH-1:0] rdatareg;        // AXI read data register
  reg arreadyreg;                           // false when write address has been latched
  reg rvalidreg;                            // true when read data out is valid
  reg awreadyreg;                           // false when write address has been latched
  reg wreadyreg;                            // false when write data has been latched
  reg bvalidreg;                            // true when write response is valid
   
//
// read transaction strategy:
// 1. at reset, assert arready, to be able to accept address transfers 
// 2. when arvalid is true, signalling address transfer, deassert arready 
// 3. assert rvalid when arvalid is false 
// 4. when rvalid and rready both true, data is transferred:
// 4a. clear the data;
// 4b. deassert rvalid
// 4c. reassert arready
//

// assign AXI outputs from registered internals, and read/write complete OK
  
  assign s_axi_rdata = rdatareg;
  assign s_axi_arready = arreadyreg;
  assign s_axi_rvalid = rvalidreg;
  assign s_axi_rresp = 2'd0;
  assign s_axi_bresp = 2'd0;
  assign s_axi_awready = awreadyreg;
  assign s_axi_wready = wreadyreg;
  assign s_axi_bvalid = bvalidreg;

  
  
  always @(posedge aclk)
  begin
    if(~aresetn)
    begin
// reset to start states
      rdatareg <= {(AXI_DATA_WIDTH){1'b0}};
      arreadyreg <= 1'b1;                           // ready for address transfer
      rvalidreg <= 1'b0;                            // not ready to transfer read data
      awreadyreg <= 1'b1;                           // ready for write address
      wreadyreg <= 1'b1;                            // ready for write data
      bvalidreg <= 1'b0;                            // no write response pending
    end
    else
    begin

// implement read transactions
// read step 2. read address transaction: latch when arvalid and arready both true    
      if(s_axi_arvalid & arreadyreg)
      begin
        arreadyreg <= 1'b0;                  // clear when address transaction happens
        raddrreg <= s_axi_araddr;            // latch read address
      end
// read step 3. assert rvalid & data when address is complete
      if(!arreadyreg & !rvalidreg)  // address complete: load data once, held stable until rready
      begin
        rvalidreg <= 1'b1;                                  // signal ready to complete data
        if(raddrreg[2]==1)
          rdatareg <= readdata1;
        else
          rdatareg <= readdata0;
      end
// read step 4. When rvalid and rready, terminate the transaction & clear data.
      if(rvalidreg & s_axi_rready)
      begin
        rvalidreg <= 1'b0;                                  // deassert rvalid
        arreadyreg <= 1'b1;                                 // ready for new address
        rdatareg <= {(AXI_DATA_WIDTH){1'b0}};
      end

// write transactions: registers are read only, so a write is accepted and ignored.
// this completes the handshake so a stray write cannot stall the interconnect.
      if(s_axi_awvalid & awreadyreg)
        awreadyreg <= 1'b0;
      if(s_axi_wvalid & wreadyreg)
        wreadyreg <= 1'b0;
      if((!awreadyreg | (s_axi_awvalid & awreadyreg)) & (!wreadyreg | (s_axi_wvalid & wreadyreg)) & !bvalidreg)
        bvalidreg <= 1'b1;                                  // both address and data accepted
      if(bvalidreg & s_axi_bready)
      begin
        bvalidreg <= 1'b0;
        awreadyreg <= 1'b1;
        wreadyreg <= 1'b1;
      end
    end         // if(!aresetn)
  end           // always @


endmodule