//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    1.08.2022 17:18:01
// Design Name:    axil_SPIWriter.v
// Module Name:    AXIL_SPIWriter
// Project Name:   Saturn 
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    Module to provide SPI write for Codec and Alex register interfaces

// Registers:
// note this is true even if the axi-lite bus is wider!
//  addr 0         SPI write data [31:0]        R/W
//  addr 4         SPI read data [63:32]        read only
//  addr 8         bit 0: 1 if busy             read only
//
// write transfers will stall if a shift is in progress, so consecutive writes are OK
// read transfers are not stalled. Before reaging SPI read data (0x04)
// make sure the previous write has completed (0x08 bit0=0)
//
// SPI 0 is a 16 bit SPI register and bits 15:0 are shifted. Valid_0 is asserted after shift.
//
// the design is in two parts: the AXI4 lite bus interface, and the SPI shifter.
//

// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Revision 1.1 - modified to add SPI read, and be 16 bit only
// Additional Comments: 
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1 ns / 1 ps

module AXIL_SPIWriter #
(
  parameter integer AXI_DATA_WIDTH = 32,
  parameter integer AXI_ADDR_WIDTH = 16,
  parameter integer INITIAL_VALUE_word_0 = 0,
  parameter integer SPI_CLOCK_DIVIDE = 3
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
  // SPI shifter
  //
  output reg SPICk,                         // divided SPI clock
  output wire SPIData,                      // shifter data bit
  output reg SPILoad,                       // load strobe for SPI (chip select)
  input wire SPIMISO                        // serial input
);

localparam CKDIVWIDTH = clogb2(SPI_CLOCK_DIVIDE);  // number of bits to hold clock divide count

  reg [AXI_ADDR_WIDTH-1:0] raddrreg;        // AXI read address register
  reg [AXI_ADDR_WIDTH-1:0] waddrreg;        // AXI write address register
  reg [AXI_DATA_WIDTH-1:0] rdatareg;        // AXI read data register
  reg [AXI_DATA_WIDTH-1:0] wdatareg;        // AXI write data register
  reg arreadyreg;                           // false when write address has been latched
  reg rvalidreg;                            // true when read data out is valid
  reg awreadyreg;                           // false when write address has been latched
  reg wreadyreg;                            // false when write data has been latched
  reg bvalidreg;                            // goes true when address and data completed
  reg wcompleted;                           // true when write data transfer has been completed
  reg ClearValidReg;                        // registered SPIBusy
  //
  // config register bits
  //
  reg [AXI_DATA_WIDTH-1:0] config_reg0;     // stored data for 16 bit shift out
  reg SPIValid_0;                           // true if value written to register 0 
   
//
// SPI writer registers
//
  reg [CKDIVWIDTH-1:0] clockdivide;
  reg [15:0] shiftreg;                      // SPI Shift register
  reg [15:0] shiftinreg;                    // SPI Input Shift register
  reg [15:0] SPIInWord;                     // complete SPI shifted word
  reg [2:0] SPIState;                       // state register
  reg SPIBusy;                              // busy bit
  reg ClearValid;                           // true when valid input should be cleared
  reg [15:0] SPICount;                      // counter

//////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////
// this design is in two halves: Axilite register interface, and SPI shifter.
//
// AXILITE interface
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
// 3. when data transaction completes, drop wready and record write transaction complete
// note that address and data could complete in either order, or at the same time
// 4. when both completed, assert bvalid and transfer data
// 5. when bvalid and bready, deassert bvalid & address ready
// 6. re-assert data ready signal after SPI transaction complete
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
      config_reg0 <= INITIAL_VALUE_word_0;
      rdatareg <= {(AXI_DATA_WIDTH){1'b0}};
      arreadyreg <= 1'b1;                           // ready for address transfer
      rvalidreg <= 1'b0;                            // not ready to transfer read data
      awreadyreg  <= 1'b1;              // initialise to write address ready
      wreadyreg  <= 1'b1;               // initialise to write data ready
      bvalidreg <= 1'b0;                // initialise to "not ready to complete"
      SPIValid_0 <= 0;                  // no data in register 0
      wcompleted <= 1'b0;               // no write complete yet
    end
    else
    begin
//
// if SPI shifter says clear the valid flags, clear them
//
    ClearValidReg <= ClearValid;        // registered copy, for leading edge detection
    if((ClearValid == 1) && (ClearValidReg == 0))
    begin
      SPIValid_0 <= 0;                  // no data in register 0
      wreadyreg <= 1'b1;                // reassert ready for new write
    end
//
// implement read transactions
// read step 2. read address transaction: latch when arvalid and arready both true    
//
      if(s_axi_arvalid & arreadyreg)
      begin
        arreadyreg <= 1'b0;                  // clear when address transaction happens
        raddrreg <= s_axi_araddr;            // latch read address
      end
// read step 3. assert rvalid & data when address is complete
      if(!arreadyreg)         // address complete
      begin
        rvalidreg <= 1'b1;                                  // signal ready to complete data
        if(raddrreg[3:2]==2'b00)                            // read back reg 0
          rdatareg <= config_reg0;
        else if(raddrreg[3:2]==2'b01)                       // read back reg 1
          rdatareg <= {16'b0, SPIInWord};
        else
          rdatareg <= {{(AXI_DATA_WIDTH-1){1'b0}}, SPIBusy};
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
        wcompleted <= 1'b1;                  // have had a write data transaction
      end

// detect data transaction and address transaction completed
      if (( s_axi_awvalid & awreadyreg & s_axi_wvalid & wreadyreg)       // both address and data complete at same time, and we are ready for data 
       || (wcompleted & s_axi_awvalid & awreadyreg)                      // data completed, and address completes
       || (!awreadyreg & s_axi_wvalid & wreadyreg))                      // address completed, and data completes
       begin
         bvalidreg <= 1'b1;
       end

// can't complete the cycle until the SPI shifter is ready. Stall here if needed.
// detect cycle complete by bready asserted too, and SPI shifter is ready; transfer data.
//      if(bvalidreg & s_axi_bready & !SPIBusy)
      if(bvalidreg & s_axi_bready)
      begin
        bvalidreg <= 1'b0;                                  // clear valid when done
        awreadyreg <= 1'b1;                                 // and reassert the readys
//        wreadyreg <= 1'b1;                                // NOT reasserting this yet
        wcompleted <= 1'b0;                                 // ready for next cycle
        if(waddrreg[2]==0)
        begin
          config_reg0 <= wdatareg;
          SPIValid_0 <= 1;
        end
      end 
    end         // if(!aresetn)
  end           // always @



//
// SPI clock divider
// SPICk target frequency approx 20MHz; divided from master clock.
// note this is TWICE the final SPI clock rate as the SPI clock is
// derived from two cycles at this rate.
// done by counting down from (divide ratio-1) to 0 inclusive
// assert SPICk for half the cycles.
//
    always @(posedge aclk)
    begin
        if(!aresetn)                // reset condition
            clockdivide <= 0;
        else                        // normal processing
        begin
        if (clockdivide == 0)
            clockdivide <= (SPI_CLOCK_DIVIDE-1);
        else
            clockdivide <= clockdivide - 1'b1;
        end  
    end

///////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////
//
// SPI Shifter
//
// SPI target device is a Codec: it can be:
// TLV320AIC23B (shifts in data in rsing edge of SCLK), or
// TLV320AIC3204 (shifts data in on falling edge of SCLK and shifts data out on rising edge)
// there is a timing diagram in the documentation folder
//
    assign SPIData = shiftreg[15];        // o/p from top bit
    always @(posedge aclk)
    begin
        if(!aresetn)                // reset condition
        begin
            SPILoad <= 1;
            shiftreg <= 0;
            shiftinreg <= 0;
            SPIInWord <= 0;
            SPIState <= 0;                              // idle state
            SPIBusy <= 0;                               // not busy
            ClearValid <= 0;                            // don't clear
            SPICount <= 0;                              // count value register
        end
        else if (clockdivide == 0)  // normal processing
        begin
            case(SPIState)
            // on entry to state 1: load counter; load shift register; assert SPIBusy; Deassert SPILoad
            0:  begin                           // idle state
                    if(SPIValid_0 == 1)
                    begin
                        SPICount <= 15;                 // 16 bit shift
                        shiftreg[15:0] <= config_reg0[15:0];        // data out is assigned from top bit
                        SPIBusy <= 1;                   // shifter is now working
                        SPIState <= 1;                  // next state
                        SPILoad <= 0;                   // deassert load
                    end
                    SPICk <= 0;
                end

            // states 1-4 are the progression through one clock cycle
            1:  begin                                   // start of clock cycle state
                    SPICk <= 1;
                    SPIState <= 2;                      // next state
                end
                
            // state 2: clock remains high
            2:  begin                                   // clock low state
                    SPIState <= 3;                      // next state always state 3
                    SPICk <= 1;
                end

            // state 3: drive clock low at the end, and sample data in
            3:  begin                                   // clock low state
                    SPIState <= 4;                      // next state always state 4
                    SPICk <= 0;
                    shiftinreg[0] <= SPIMISO;           // add in new data bit
                end

            // End of clock cycle. if counter == 0, assert ClearValid & move on else next lap
            4:  begin                                   // clock low state
                    if(SPICount == 0)                   // go to an end state
                    begin
                        SPIState <= 5;                  // goto 1st end type
                        ClearValid <= 1;
                    end
                    else                                // else loop round
                    begin
                        SPIState <= 1;                  // next state is state 1
                        SPICount <= SPICount - 1;
                        shiftreg <= (shiftreg << 1);    // left shift for next bit
                        shiftinreg <= (shiftinreg << 1);   // left shift for next bit
                    end
                    SPICk <= 0;
                end

            // end state. Deassert chip select out
            5:  begin                               // clock low state
                    ClearValid <= 0;
                    SPIInWord <= shiftinreg;        // save shifted data  
                    SPIState <= 6;                  // next state always state 3
                    SPICk <= 0;
                    SPIBusy <= 0;
                    SPILoad <= 1;                   // deassert load

                end

            // near end state
            6:  begin                           // clock low state
                    SPIState <= 7;                  // next state always state 3
                    SPICk <= 0;
                end

            // final state: go back to the start
            7:  begin                           // clock low state
                    SPIState <= 0;                  // next state always state 0
                end


            endcase
        end
    end


//
// function to find a register size to hold a given sized integer
//
function integer clogb2;
input [31:0] depth;
begin
  for(clogb2=0; depth>0; clogb2=clogb2+1)
  depth = depth >> 1;
end
endfunction

endmodule