`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    15.03.2021 17:18:01
// Design Name:    stream_reader
// Module Name:    AXI_Stream_Reader
// Project Name:   Pluto 
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    Read from an AXI-4 Stream to an AXI4-Lite slave interfasce
//                 The AXI read address is ignored, so this works with a DMA with 
//                 incrementing address that reads from the one port. 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1 ns / 1 ps

module AXI_Stream_Reader #
(
  parameter integer AXI_DATA_WIDTH = 32,
  parameter integer AXI_ADDR_WIDTH = 16
)
(
  // System signals
  input  wire                      aclk,
  input  wire                      aresetn,

  // Slave side
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

  // Slave side
  output wire                      s_axis_tready,
  input  wire [AXI_DATA_WIDTH-1:0] s_axis_tdata,
  input  wire                      s_axis_tvalid
);

  reg [AXI_DATA_WIDTH-1:0] rdatareg;
  reg arreadyreg;                           // false when write address has been latched
  reg treadyreg;                            // false when axi stream data in latched
  reg rvalidreg;                            // true when read data out is valid
   
//
// strategy:
// 1. at reset, assert arready and tready, to be able to accept address and stream transfers 
// 2. latch the incoming stream data as soon as it is available (this should be before a bus read happens)
// 2a. dassert tready once latched
// 3. when arvalid is true, signalling address transfer, deassert arready 
// 4. assert rvalid when arvalid is false, and tready is false 
// 5. when rvalid and rready both true, data is transferred:
// 5a. clear the data;
// 5b. deassert rvalid
// 5c. reassert tready    
// 5d. reassert arready
//

  assign s_axi_rdata = rdatareg;
  assign s_axi_arready = arreadyreg;
  assign s_axis_tready = treadyreg;
  assign s_axi_rvalid = rvalidreg;

  always @(posedge aclk)
  begin
    if(~aresetn)
    begin
// step 1
      rdatareg <= {(AXI_DATA_WIDTH){1'b0}};
      arreadyreg <= 1'b1;                           // ready for address transfer
      treadyreg <= 1'b1;                            // ready for stream data
      rvalidreg <= 1'b0;                            // not ready to transfer read data
    end
    else
    begin
// step 2. axi stream slave data transfer: latch data & clear tready when valid is true
      if(s_axis_tvalid & treadyreg)
      begin
        treadyreg <= 1'b0;                  // clear when data transaction happens
        rdatareg <= s_axis_tdata;           // latch data
      end
// step 3. read address transaction: latch when arvalid and arready both true    
      if(s_axi_arvalid & arreadyreg)
      begin
        arreadyreg <= 1'b0;                  // clear when address transaction happens
      end
// step 4. assert vvalid when address and stream data transfers are ready
      if((s_axi_arvalid & arreadyreg & !treadyreg) ||       // address complete and stream already complete
      (!arreadyreg & s_axis_tvalid & treadyreg))            // address already complete & stream complete
      begin
        rvalidreg <= 1'b1;                                  // signal ready to complete data
      end
// step 5. When rvalid and rready, terminate the transaction & clear data.
      if(rvalidreg & s_axi_rready)
      begin
        rvalidreg <= 1'b0;                                  // deassert rvalid
        arreadyreg <= 1'b1;                                 // ready for new address
        treadyreg <= 1'b1;                                  // ready for new stream data
        rdatareg <= {(AXI_DATA_WIDTH){1'b0}};
      end
    end
  end

// drive output from registered internals
  assign s_axi_arready = arreadyreg;
  assign s_axi_rdata = rdatareg;
  assign s_axi_rvalid = rvalidreg;
  assign s_axis_tready = treadyreg;
  assign s_axi_rresp = 2'd0;
// and outputs to make sure we don't respond to a write
  assign s_axi_bresp = 2'd0;                         // no response to write access
  assign s_axi_awready = 1'b0;                       // no response to write access
  assign s_axi_wready = 1'b0;                        // no response to write access
  assign s_axi_bvalid = 1'b0;                        // no response to write access

endmodule