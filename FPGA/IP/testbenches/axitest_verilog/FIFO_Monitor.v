//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    29/9/2023
// Design Name:    FIFO Monitor
// Module Name:    FIFO_Monitor
// Project Name:   Saturn 
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    Module to allow processor to monitor 4 FIFOs.
//                 Detect and latch FIFO under or overflow, potentially to generate interrupt.
//                 Allow readback of FIFO current depth and overflow state
//                 AXI4-Lite bus interface to processor 
// Registers:
//  addr 0         Status register 1 (read only, with side effect)
//  addr 4         Status register 2 (read only, with side effect)
//  addr 8         Status register 3 (read only, with side effect)
//  addr C         Status register 4 (read only, with side effect)
//     bit(15:0)   Current FIFO Depth
//     bit 29      1 id an underflow has occurred, from depth
//     bit 30      1 if an overflow has occurred, from depth 
//     bit 31      1 if an overflow has occurred, from FIFO flag. 
//     bits 29-31 Cleared by read.
//
//  addr 10         Control register 1 (read/write, with no read side effect)
//  addr 14         Control register 1 (read/write, with no read side effect)
//  addr 18         Control register 1 (read/write, with no read side effect)
//  addr 1C         Control register 1 (read/write, with no read side effect)
//     bit(15:0)   Threshold FIFO depth
//     bit 31      Interrupt enable
//
// FIFO Interface signals:
//     FIFOn_Words(31:0)      current FIFO depth (note only 16 bits considered valid)
//     FIFOn_Overflow         if 1, an over(or under) flow has occurred 

// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Revision 2 - update to latch underflow and overflow. remove "read or write FIFO" 
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1 ns / 1 ps

module FIFO_Monitor #
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
  // FIFO interface 
  // note the Xilinx FIFO reports the number of words held through both read and write side
  //
  input wire [31:0]                fifo1_count,    // current number of words in FIFO
  input wire                       fifo1_overflow, // if 1, an over(or under) flow has occurred 
  input wire [31:0]                fifo2_count,    // current number of words in FIFO
  input wire                       fifo2_overflow, // if 1, an over(or under) flow has occurred 
  input wire [31:0]                fifo3_count,    // current number of words in FIFO
  input wire                       fifo3_overflow, // if 1, an over(or under) flow has occurred 
  input wire [31:0]                fifo4_count,    // current number of words in FIFO
  input wire                       fifo4_overflow, // if 1, an over(or under) flow has occurred 

// interrupt
  output wire                      int1_out,       // interrupt output 1 for interrupt
  output wire                      int2_out,       // interrupt output 1 for interrupt
  output wire                      int3_out,       // interrupt output 1 for interrupt
  output wire                      int4_out        // interrupt output 1 for interrupt
);

  reg [15:0] fifo1_threshold;                // writable register - threshold to trigger intr
  reg [15:0] fifo1_count_reg;                // current FIFO word count
  reg int1_enable;                           // 1 enables interrupt generation
  reg fifo1_overflowed;                      // set true if FIFO has under/overflowed (from FIFO bit)
  reg fifo1_over_threshold;                  // set if FIFO exceeds threshold
  reg fifo1_underflowed;                     // set if FIFO emptied (from count)
  reg interrupt1_out;                        // interrupt bit out 

  reg [15:0] fifo2_threshold; // writable register - threshold to trigger intr
  reg [15:0] fifo2_count_reg; // current FIFO word count
  reg int2_enable;                           // 1 enables interrupt generation
  reg fifo2_overflowed;                      // set true if FIFO has under/overflowed
  reg fifo2_over_threshold;                  // set if FIFO exceeds threshold
  reg fifo2_underflowed;                     // set if FIFO emptied (from count)
  reg interrupt2_out;                        // interrupt bit out 

  reg [15:0] fifo3_threshold; // writable register - threshold to trigger intr
  reg [15:0] fifo3_count_reg; // current FIFO word count
  reg int3_enable;                           // 1 enables interrupt generation
  reg fifo3_overflowed;                      // set true if FIFO has under/overflowed
  reg fifo3_over_threshold;                  // set if FIFO exceeds threshold
  reg fifo3_underflowed;                     // set if FIFO emptied (from count)
  reg interrupt3_out;                        // interrupt bit out 

  reg [15:0] fifo4_threshold; // writable register - threshold to trigger intr
  reg [15:0] fifo4_count_reg; // current FIFO word count
  reg int4_enable;                           // 1 enables interrupt generation
  reg fifo4_overflowed;                      // set true if FIFO has under/overflowed
  reg fifo4_over_threshold;                  // set if FIFO exceeds threshold
  reg fifo4_underflowed;                     // set if FIFO emptied (from count)
  reg interrupt4_out;                        // interrupt bit out 

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

  assign int1_out = interrupt1_out;
  assign int2_out = interrupt2_out;
  assign int3_out = interrupt3_out;
  assign int4_out = interrupt4_out;
  
  
  always @(posedge aclk)
  begin
    if(~aresetn)
    begin
// reset to start states
      rdatareg <= {(AXI_DATA_WIDTH){1'b0}};
      arreadyreg <= 1'b1;                           // ready for address transfer
      rvalidreg <= 1'b0;                            // not ready to transfer read data
      awreadyreg  <= 1'b1;                          // initialise to write address ready
      wreadyreg  <= 1'b1;                           // initialise to write data ready
      bvalidreg <= 1'b0;                            // initialise to "not ready to complete"
// clear the FIFO registers      
      fifo1_threshold <= {32{1'b0}};                // zero the FIFO threshold
      int1_enable <= 1'b0;
      fifo1_overflowed <= 1'b0;
      interrupt1_out <= 1'b0;
      fifo1_over_threshold <= 1'b0;
      fifo1_underflowed <= 1'b0;

      fifo2_threshold <= {32{1'b0}};                // zero the FIFO threshold
      int2_enable <= 1'b0;
      fifo2_overflowed <= 1'b0;
      interrupt2_out <= 1'b0;
      fifo2_over_threshold <= 1'b0;
      fifo2_underflowed <= 1'b0;

      fifo3_threshold <= {32{1'b0}};                // zero the FIFO threshold
      int3_enable <= 1'b0;
      fifo3_overflowed <= 1'b0;
      interrupt3_out <= 1'b0;
      fifo3_over_threshold <= 1'b0;
      fifo3_underflowed <= 1'b0;

      fifo4_threshold <= {32{1'b0}};                // zero the FIFO threshold
      int4_enable <= 1'b0;
      fifo4_overflowed <= 1'b0;
      interrupt4_out <= 1'b0;
      fifo4_over_threshold <= 1'b0;
      fifo4_underflowed <= 1'b0;
    end
    else
    begin
//
// collect FIFO state to internal registers
// latch overflow and underflow indications so they are stored until read
// FIFO 1
//
      fifo1_count_reg <= fifo1_count;           // latch the current FIFO data count
      if(fifo1_overflow)                        // if FIFO overflow flag, set the bit
        fifo1_overflowed <= 1'b1;               // set persistently

      if(fifo1_count_reg >= fifo1_threshold)
        fifo1_over_threshold <= 1'b1;
      else if(fifo1_count_reg == 0)
        fifo1_underflowed <= 1'b1;
      interrupt1_out <= (int1_enable & (fifo1_overflowed | fifo1_over_threshold | fifo1_underflowed));
//
// FIFO 2
//
      fifo2_count_reg <= fifo2_count;           // latch the current FIFO data count
      if(fifo2_overflow)                        // if FIFO overflow flag, set the bit
        fifo2_overflowed <= 1'b1;               // set persistently

      if(fifo2_count_reg >= fifo2_threshold)
        fifo2_over_threshold <= 1'b1;
      else if(fifo2_count_reg == 0)
        fifo2_underflowed <= 1'b1;
      interrupt2_out <= (int2_enable & (fifo2_overflowed | fifo2_over_threshold | fifo2_underflowed));
//
// FIFO 3
//
      fifo3_count_reg <= fifo3_count;           // latch the current FIFO data count
      if(fifo3_overflow)                        // if FIFO overflow flag, set the bit
        fifo3_overflowed <= 1'b1;               // set persistently

      if(fifo3_count_reg >= fifo3_threshold)
        fifo3_over_threshold <= 1'b1;
      else if(fifo3_count_reg == 0)
        fifo3_underflowed <= 1'b1;
      interrupt3_out <= (int3_enable & (fifo3_overflowed | fifo3_over_threshold | fifo3_underflowed));
//
// FIFO 4
//
      fifo4_count_reg <= fifo4_count;           // latch the current FIFO data count
      if(fifo4_overflow)                        // if FIFO overflow flag, set the bit
        fifo4_overflowed <= 1'b1;               // set persistently

      if(fifo4_count_reg >= fifo4_threshold)
        fifo4_over_threshold <= 1'b1;
      else if(fifo4_count_reg == 0)
        fifo4_underflowed <= 1'b1;
      interrupt4_out <= (int4_enable & (fifo4_overflowed | fifo4_over_threshold | fifo4_underflowed));

//
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
        case (raddrreg[4:2])
        0:  rdatareg <= {fifo1_overflowed, fifo1_over_threshold, fifo1_underflowed,
                    {(AXI_DATA_WIDTH - 19){1'b0}}, 
                    fifo1_count_reg};                        // concat data
        1:  rdatareg <= {fifo2_overflowed, fifo2_over_threshold, fifo2_underflowed,
                    {(AXI_DATA_WIDTH - 19){1'b0}}, 
                    fifo2_count_reg};                        // concat data
        2:  rdatareg <= {fifo3_overflowed, fifo3_over_threshold, fifo3_underflowed,
                    {(AXI_DATA_WIDTH - 19){1'b0}}, 
                    fifo3_count_reg};                        // concat data
        3:  rdatareg <= {fifo4_overflowed, fifo4_over_threshold, fifo4_underflowed,
                    {(AXI_DATA_WIDTH - 19){1'b0}}, 
                    fifo4_count_reg};                        // concat data
        4: rdatareg <= {int1_enable,  
                    {(AXI_DATA_WIDTH - 16 - 1){1'b0}}, 
                    fifo1_threshold};                        //concat 
        5: rdatareg <= {int2_enable,  
                    {(AXI_DATA_WIDTH - 16 - 1){1'b0}}, 
                    fifo2_threshold};                        //concat 
        6: rdatareg <= {int3_enable,  
                    {(AXI_DATA_WIDTH - 16 - 1){1'b0}}, 
                    fifo3_threshold};                        //concat 
        7: rdatareg <= {int4_enable,  
                    {(AXI_DATA_WIDTH - 16 - 1){1'b0}}, 
                    fifo4_threshold};                        //concat 
        endcase
      end
// read step 4. When rvalid and rready, terminate the transaction & clear data.
      if(rvalidreg & s_axi_rready)
      begin
        rvalidreg <= 1'b0;                                  // deassert rvalid
        arreadyreg <= 1'b1;                                 // ready for new address
        rdatareg <= {(AXI_DATA_WIDTH){1'b0}};
        case (raddrreg[4:2])
          0: begin 
                fifo1_overflowed <= 0; 
                fifo1_over_threshold <= 0; 
                fifo1_underflowed <= 0; 
          end             // clear on data transfer

          1: begin 
                fifo2_overflowed <= 0; 
                fifo2_over_threshold <= 0; 
                fifo2_underflowed <= 0; 
          end             // clear on data transfer

          2: begin 
                fifo3_overflowed <= 0; 
                fifo3_over_threshold <= 0; 
                fifo3_underflowed <= 0; 
          end             // clear on data transfer

          3: begin 
                fifo4_overflowed <= 0; 
                fifo4_over_threshold <= 0; 
                fifo4_underflowed <= 0; 
          end             // clear on data transfer
        endcase
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
        case (waddrreg[4:2])
          4: begin
               fifo1_threshold <= ( wdatareg & {16{1'b1}});      // subset
               int1_enable <= (wdatareg >> (AXI_DATA_WIDTH-1)) & 1'b1;
             end
          5: begin
               fifo2_threshold <= ( wdatareg & {16{1'b1}});      // subset
               int2_enable <= (wdatareg >> (AXI_DATA_WIDTH-1)) & 1'b1;
             end
          6: begin
               fifo3_threshold <= ( wdatareg & {16{1'b1}});      // subset
               int3_enable <= (wdatareg >> (AXI_DATA_WIDTH-1)) & 1'b1;
             end
          7: begin
               fifo4_threshold <= ( wdatareg & {16{1'b1}});      // subset
               int4_enable <= (wdatareg >> (AXI_DATA_WIDTH-1)) & 1'b1;
             end
        endcase
      end 

    end         // if(!aresetn)
  end           // always @


endmodule