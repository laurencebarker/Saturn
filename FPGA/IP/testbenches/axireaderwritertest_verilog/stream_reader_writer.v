`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    07.05.2021 16:42:01
// Design Name:    stream_reader_writer
// Module Name:    AXI_Stream_Reader_Writer
// Project Name:   Saturn 
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    Write and read AXI-4 Streams from an AXI4 slave interfasce
//                 The AXI address is ignored, so this works with a DMA
//                 with incrementing address that writes from the one port. 
//
//                 This is a core in two halves: a stream writer and a stream reader.
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// the current implementation is not very efficient; at best it will bo one data "beat" per two clocks.
// that could be improved by "looking ahead" to the AXI stream transactions, to know that data will
// be available in the next cycle or the buffer will have been cleared in the next cycle.
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1 ns / 1 ps

module AXI_Stream_Reader_Writer #
(
  parameter integer AXI_DATA_WIDTH = 32,
  parameter integer AXI_ADDR_WIDTH = 16,
  parameter AXI_ID_WIDTH = 8
)
(
  // System signals
  input  wire                      aclk,
  input  wire                      aresetn,

  // Slave side
  input  wire [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,  // AXI4 slave: Write address
  input  wire                      s_axi_awvalid, // AXI4 slave: Write address valid
  output wire                      s_axi_awready, // AXI4 slave: Write address ready
  input wire [AXI_ID_WIDTH-1:0]    s_axi_awid,    // AXI4 slave: Write address ID      
  input wire [7:0]                 s_axi_awlen,   // AXI4 slave: Write burst length (not used)
  input wire [2:0]                 s_axi_awsize,  // AXI4 slave: data bytes per beat (not used)
  input wire [1:0]                 s_axi_awburst, // AXI4 slave: burst type (not used)
  input  wire [AXI_DATA_WIDTH-1:0] s_axi_wdata,   // AXI4 slave: Write data
  input  wire                      s_axi_wvalid,  // AXI4 slave: Write data valid
  output wire                      s_axi_wready,  // AXI4 slave: Write data ready
  input wire [(AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb, // AXI4 slave: Write strobes (not used)
  input  wire                      s_axi_wlast,   // AXI4 slave: Write burst last beat
  output wire [1:0]                s_axi_bresp,   // AXI4 slave: Write response
  output wire                      s_axi_bvalid,  // AXI4 slave: Write response valid
  input  wire                      s_axi_bready,  // AXI4 slave: Write response ready
  input  wire [AXI_ADDR_WIDTH-1:0] s_axi_araddr,  // AXI4 slave: Read address
  input  wire                      s_axi_arvalid, // AXI4 slave: Read address valid
  output wire                      s_axi_arready, // AXI4 slave: Read address ready
  input wire [AXI_ID_WIDTH-1:0]    s_axi_arid,    // AXI4 slave: Read address ID      
  input wire [7:0]                 s_axi_arlen,   // AXI4 slave: Read burst length (not used)
  input wire [2:0]                 s_axi_arsize,  // AXI4 slave: data bytes per beat (not used)
  input wire [1:0]                 s_axi_arburst, // AXI4 slave: burst type (not used)
  output wire [AXI_DATA_WIDTH-1:0] s_axi_rdata,   // AXI4 slave: Read data
  output wire [1:0]                s_axi_rresp,   // AXI4 slave: Read data response
  output wire [AXI_ID_WIDTH-1:0]   s_axi_rid,     // AXI4 slave: Read data ID      
  output wire                      s_axi_rlast,   // AXI4 slave: Read burst last beat
  output wire                      s_axi_rvalid,  // AXI4 slave: Read data valid
  input  wire                      s_axi_rready,  // AXI4 slave: Read data ready

  // AXI stream Master (for AXI rwrite transactions) 
  output wire [AXI_DATA_WIDTH-1:0] m_axis_tdata,
  output wire                      m_axis_tvalid,
  input wire                       m_axis_tready,

  // AXI stream Slave (for AXI read transactions)
  output wire                      s_axis_tready,
  input  wire [AXI_DATA_WIDTH-1:0] s_axis_tdata,
  input  wire                      s_axis_tvalid,
  
  // activity indicator (1 bit if read or write transfer occurs)
  output wire Activity
);

  reg awreadyreg;                            // false when write address has been latched
  reg wreadyreg;                             // false when write data has been latched
  reg bvalidreg;                             // goes true when address and data completed
  reg m_axis_tvalidreg;                      // goes true when bvalid presented
  reg [AXI_DATA_WIDTH-1:0] write_data;

  reg [AXI_DATA_WIDTH-1:0] rdatareg;
  reg [7:0]                rlenreg;          // burst length register
  reg [AXI_ID_WIDTH-1:0]   ridreg;           // read ID
  reg wlastreg;                              // goes true when last write data transferred
  reg rlastreg;                              // goes true when last read data transferred
  reg arreadyreg;                            // false when write address has been latched
  reg s_axis_treadyreg;                      // false when axi stream data in latched
  reg rvalidreg;                             // true when read data out is valid
  reg ActivityReg;                           // set true when a transfer occurs


// strategy for write transaction:
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
  assign s_axi_bresp = 2'd0;
  assign m_axis_tvalid = m_axis_tvalidreg;
  assign m_axis_tdata = write_data;
  
  assign Activity = ActivityReg;
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
      m_axis_tvalidreg <= 1'b0;         // initialise to "no data"
      write_data <= {(AXI_DATA_WIDTH){1'b0}};
      wlastreg <= 0;                    // clear latched last;
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
        m_axis_tvalidreg <= 1'b1;            // assert valid for axi slave
        if(s_axi_wlast)
            wlastreg <= 1;
      end

// detect data transaction and address transaction completed
      if (( s_axi_awvalid & awreadyreg & s_axi_wvalid & s_axi_wlast & wreadyreg)      // both address and data complete at same time 
       || (wlastreg & s_axi_awvalid & awreadyreg)                     // data completed 1st, and address completes
       || (!awreadyreg & s_axi_wvalid & s_axi_wlast & wreadyreg))                     // address completed 1st, and data completes
       begin
         bvalidreg <= 1'b1;
       end

// detect cycle complete by bready asserted too
      if(bvalidreg & s_axi_bready)
      begin
        bvalidreg <= 1'b0;                                  // clear valid when done
        awreadyreg <= 1'b1;                                 // and reassert the readys
        wlastreg <= 0;                                      // clear latched last;
      end 
       
// finally axi stream valid only asserted until ready handshake
      if(m_axis_tvalidreg & m_axis_tready)
      begin
        m_axis_tvalidreg <= 1'b0;                  // deassert valid for axi slave
        wreadyreg <= 1'b1;
      end
      
    end         // not reset
  end

//
// read transaction strategy:
// modified from 1st version so that it only initiates a FIFO read once the bus read has begun.
// this is so that the true FIFO depth can be established beforehand
// (if the FIFO reader held a word, that couldn't be counted but wasn't known)
// 1. at reset, assert arready, to be able to accept address transfer 
// 2. when arvalid is true, signalling address transfer, deassert arready & assert tready 
// 3. latch the incoming stream data as soon as it is available (this should be before a bus read happens)
// 3a. dassert tready once latched
// 4. when rvalid and rready both true, data is transferred:
// 4a. clear the data;
// 4b. deassert rvalid
// 4c. reassert tready    
// 4d. reassert arready
//

  assign s_axi_rdata = rdatareg;
  assign s_axi_arready = arreadyreg;
  assign s_axi_rvalid = rvalidreg;
  assign s_axi_rid = ridreg;
  assign s_axi_rlast = (rlenreg==0);
  assign s_axi_rresp = 2'd0;
  assign s_axis_tready = s_axis_treadyreg;

  always @(posedge aclk)
  begin
    if(~aresetn)
    begin
// step 1
      rdatareg <= {(AXI_DATA_WIDTH){1'b0}};
      arreadyreg <= 1'b1;                           // ready for address transfer
      s_axis_treadyreg <= 1'b0;                     // ready for stream data
      rvalidreg <= 1'b0;                            // not ready to transfer read data
      rlastreg <= 1'b0;                             // not last data
      rlenreg <= 8'b0;                              // clear burst length
      ridreg <= {(AXI_ID_WIDTH){1'b0}};             // clear ID register
    end
    else
    begin
// step 2. read address transaction: latch when arvalid and arready both true    
      if(s_axi_arvalid & arreadyreg)
      begin
        arreadyreg <= 1'b0;                  // clear when address transaction happens
        rlenreg <= s_axi_arlen;              // store burst length
        ridreg <= s_axi_arid;                // store transaction ID 
        s_axis_treadyreg <= 1'b1;            // ready for stream data
      end
// step 3. axi stream slave data transfer: latch data & clear tready when valid is true
// only do this when a read transaction has begun
      if(s_axis_tvalid & s_axis_treadyreg & !arreadyreg)
      begin
        s_axis_treadyreg <= 1'b0;           // clear when data transaction happens
        rdatareg <= s_axis_tdata;           // latch data
        rvalidreg <= 1'b1;                                  // signal ready to complete data
      end
// step 4. When rvalid and rready, terminate the transaction & clear data.
      if(rvalidreg & s_axi_rready)
      begin
        rvalidreg <= 1'b0;                                  // deassert rvalid
        rdatareg <= {(AXI_DATA_WIDTH){1'b0}};
        if (rlenreg != 0)                                   // decrement beat count
        begin
          rlenreg <= rlenreg-1;
          s_axis_treadyreg <= 1'b1;                           // ready for new stream data
        end
        else
        begin
          arreadyreg <= 1'b1;                                 // ready for new address
          ridreg <= {(AXI_ID_WIDTH){1'b0}};                   // clear ID register
          s_axis_treadyreg <= 1'b0;                           // NOT ready for new stream data
        end
      end
    end
  end


  always @(posedge aclk)
  begin
    if(~aresetn)
    begin
        ActivityReg <= 0;
    end
    else
    begin
        ActivityReg <= ((m_axis_tvalidreg & m_axis_tready) || (s_axis_tvalid & s_axis_treadyreg));
    end
  end

endmodule
