//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    12.07.2021 17:18:01
// Design Name:    axil_config256_reg.v
// Module Name:    AXIL_ConfigReg_256
// Project Name:   Saturn 
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    Module to provide 256 bit writeable register from axi4-lite bus
//                 Also responds to read transactions to read back
//                 AXI4-Lite bus interface to processor 
// Registers:
// note this is true even if the axi-lite bus is wider!
//  addr 00         config data [31:0]
//  addr 04         config data [63:32]
//  addr 08         config data [95:64]
//  addr 0C         config data [127:96]
//  addr 10         config data [159:128]
//  addr 14         config data [191:160]
//  addr 18         config data [223:192]
//  addr 1C         config data [255:224]

// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: 
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1 ns / 1 ps

module AXIL_ConfigReg_256 #
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

  //
  // config register bits
  //
  output reg [AXI_DATA_WIDTH-1:0] config_reg0,
  output reg [AXI_DATA_WIDTH-1:0] config_reg1,
  output reg [AXI_DATA_WIDTH-1:0] config_reg2,
  output reg [AXI_DATA_WIDTH-1:0] config_reg3,
  output reg [AXI_DATA_WIDTH-1:0] config_reg4,
  output reg [AXI_DATA_WIDTH-1:0] config_reg5,
  output reg [AXI_DATA_WIDTH-1:0] config_reg6,
  output reg [AXI_DATA_WIDTH-1:0] config_reg7
);

  reg [AXI_ADDR_WIDTH-1:0] raddrreg;        // AXI read address register
  reg [AXI_ADDR_WIDTH-1:0] waddrreg;        // AXI write address register
  reg [AXI_DATA_WIDTH-1:0] rdatareg;        // AXI read data register
  reg [AXI_DATA_WIDTH-1:0] wdatareg;        // AXI write data register
  reg arreadyreg;                           // false when write address has been latched
  reg rvalidreg;                            // true when read data out is valid
  reg awreadyreg;                            // false when write address has been latched
  reg wreadyreg;                             // false when write data has been latched
  reg bvalidreg;                             // goes true when address and data completed
   
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
// strategy for write transaction:
// 1. pre-assert awready, wready (held in registers)
// 2. when address transaction completes, drop awready 
// 3. when data transaction completes, drop wready
// note that address and data could complete in either order!
// 4. when both completed, assert bvalid and transfer data
// 5. when bvalid and bready, deassert bvalid and re-assert ready signals
// it is a requirement that there be no combinatorial path from input to output

  
// assign AXI outputs from registered internals, and read/write complete OK
  assign s_axi_rdata = rdatareg;
  assign s_axi_arready = arreadyreg;
  assign s_axi_rvalid = rvalidreg;
  assign s_axi_awready = awreadyreg;
  assign s_axi_wready = wreadyreg;
  assign s_axi_bvalid = bvalidreg;
  assign s_axi_rresp = 2'd0;
  assign s_axi_bresp = 2'd0;

  
  
  always @(posedge aclk)
  begin
    if(~aresetn)
    begin
// reset to start states
      config_reg0 <= {(AXI_DATA_WIDTH){1'b0}};
      config_reg1 <= {(AXI_DATA_WIDTH){1'b0}};
      config_reg2 <= {(AXI_DATA_WIDTH){1'b0}};
      config_reg3 <= {(AXI_DATA_WIDTH){1'b0}};
      config_reg4 <= {(AXI_DATA_WIDTH){1'b0}};
      config_reg5 <= {(AXI_DATA_WIDTH){1'b0}};
      config_reg6 <= {(AXI_DATA_WIDTH){1'b0}};
      config_reg7 <= {(AXI_DATA_WIDTH){1'b0}};
      rdatareg <= {(AXI_DATA_WIDTH){1'b0}};
      arreadyreg <= 1'b1;                           // ready for address transfer
      rvalidreg <= 1'b0;                            // not ready to transfer read data
      awreadyreg  <= 1'b1;              // initialise to write address ready
      wreadyreg  <= 1'b1;               // initialise to write data ready
      bvalidreg <= 1'b0;                // initialise to "not ready to complete"
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
      if(!arreadyreg)         // address complete
      begin
        rvalidreg <= 1'b1;                                  // signal ready to complete data
	case(raddrreg[4:2])
	  0: rdatareg <= config_reg0;
	  1: rdatareg <= config_reg1;
	  2: rdatareg <= config_reg2;
	  3: rdatareg <= config_reg3;
	  4: rdatareg <= config_reg4;
	  5: rdatareg <= config_reg5;
	  6: rdatareg <= config_reg6;
	  7: rdatareg <= config_reg7;
	endcase
      end
// read step 4. When rvalid and rready, terminate the transaction & clear data.
      if(rvalidreg & s_axi_rready)
      begin
        rvalidreg <= 1'b0;                                  // deassert rvalid
        arreadyreg <= 1'b1;                                 // ready for new address
        rdatareg <= {(AXI_DATA_WIDTH){1'b0}};
      end


// write step 2 address transaction: latch when awvalid and awready both true    
      if(s_axi_awvalid & awreadyreg)
      begin
        waddrreg <= s_axi_awaddr;            // latch write address
        awreadyreg <= 1'b0;                  // clear when address transaction happens
      end

// write step 3 data transaction:   latch when wvalid and wready both true   
      if(s_axi_wvalid & wreadyreg)
      begin
        wdatareg <= s_axi_wdata;             // latch write data
        wreadyreg <= 1'b0;                   // clear when address transaction happens
      end

// detect data transaction and address transaction completed
      if (( s_axi_awvalid & awreadyreg & s_axi_wvalid & wreadyreg)      // both address and data complete at same time 
       || (!wreadyreg & s_axi_awvalid & awreadyreg)                     // data completed, and address completes
       || (!awreadyreg & s_axi_wvalid & wreadyreg))                     // address completed, and data completes
       begin
         bvalidreg <= 1'b1;
       end

// detect cycle complete by bready asserted too; transfer data.
      if(bvalidreg & s_axi_bready)
      begin
        bvalidreg <= 1'b0;                                  // clear valid when done
        awreadyreg <= 1'b1;                                 // and reassert the readys
        wreadyreg <= 1'b1;
	case(waddrreg[4:2])
	  0: config_reg0 <= wdatareg;
	  1: config_reg1 <= wdatareg;
	  2: config_reg2 <= wdatareg;
	  3: config_reg3 <= wdatareg;
	  4: config_reg4 <= wdatareg;
	  5: config_reg5 <= wdatareg;
	  6: config_reg6 <= wdatareg;
	  7: config_reg7 <= wdatareg;
	endcase
      end 
    end         // if(!aresetn)
  end           // always @


endmodule