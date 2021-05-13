`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    15.03.2021 17:18:01
// Design Name:    stream_writer
// Module Name:    AXI_Stream_Writer
// Project Name:   Pluto 
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    Write an AXI-4 Stream from an AXI4-Lite slave interfasce
//                 The AXI write address is ignored, so this works with a DMA
//                 with incrementing address that writes from the one port. 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1 ns / 1 ps

module AXI_Stream_Writer #
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

  // Master side
  output wire [AXI_DATA_WIDTH-1:0] m_axis_tdata,
  output wire                      m_axis_tvalid
);

  reg awreadyreg;                            // false when write address has been latched
  reg wreadyreg;                             // false when write data has been latched
  reg bvalidreg;                             // goes true when address and data completed
  reg tvalidreg;                             // goes true when bvalid presented
  reg [AXI_DATA_WIDTH-1:0] write_data;

// strategy for transaction:
// 1. pre-assert awready, wready (held in registers)
// 2. when address transaction completes, drop awready 
// 3. when data transaction completes, drop wready
// 4. when both completed, assert bvalid
// 5. when bvalid and bready, deassert bvalid and re-assert ready signals
// 6. on 1st cycle when bvalid asserted, assert axis_valid 
// it is a requirement that there be no combinatorial path from input to output
//
  assign s_axi_awready = awreadyreg;
  assign s_axi_wready = wreadyreg;
  assign s_axi_bvalid = bvalidreg;
  assign m_axis_tvalid = tvalidreg;
  assign m_axis_tdata = write_data;
//
// now set the "address latched" when address valid and ready are true
// set "data latched" when data valid and ready are true
// clear both when response valid and rteady are true
// set output valid when both are true 
//
  always @(posedge aclk)
  begin
    if(~aresetn)
    begin
      awreadyreg  <= 1'b1;              // initialise to ready
      wreadyreg  <= 1'b1;               // initialise to ready
      bvalidreg <= 1'b0;                // initialise to "not ready to complete"
      tvalidreg <= 1'b0;                // initialise to "no data"
      write_data <= {(AXI_DATA_WIDTH){1'b0}};
    end
    else        // not reset
    begin
// basic address transaction: latch when awvalid and awready both true    
      if(s_axi_awvalid & awreadyreg)
      begin
        awreadyreg <= 1'b0;                  // clear when address transaction happens
      end

// basic data transaction:   latch when wvalid and wready both true   
      if(s_axi_wvalid & wreadyreg)
      begin
        wreadyreg <= 1'b0;                   // clear when address transaction happens
        write_data <= s_axi_wdata;
        tvalidreg <= 1'b1;                  // assert valid for axi slave
      end

// detect data transaction and address transaction completed
      if (( s_axi_awvalid & awreadyreg & s_axi_wvalid & wreadyreg)      // both address and data complete at same time 
       || (!wreadyreg & s_axi_awvalid & awreadyreg)                     // data completed, and address completes
       || (!awreadyreg & s_axi_wvalid & wreadyreg))                     // address completed, and data completes
       begin
         bvalidreg <= 1'b1;
       end

// detect cycle complete by bready asserted too
      if(bvalidreg & s_axi_bready)
      begin
        bvalidreg <= 1'b0;                                  // clear valid when done
        awreadyreg <= 1'b1;                                 // and reassert the readys
        wreadyreg <= 1'b1;
      end 
       
// finally axi stream valid true for one cycle only
      if(tvalidreg)
      begin
        tvalidreg <= 1'b0;                  // deassert valid for axi slave
      end
      
    end         // not reset
  end

  assign s_axi_bresp = 2'd0;
  assign s_axi_arready = 1'b0;
  assign s_axi_rdata = {(AXI_DATA_WIDTH){1'b0}};
  assign s_axi_rresp = 2'd0;
  assign s_axi_rvalid = 1'b0;

endmodule
