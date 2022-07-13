`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:  HPSDR
// Engineer: Laurence Barker G8NJJ
// 
// Create Date: 15.03.2021 17:19:26
// Design Name: ADC78H90 ADC reader
// Module Name: AXI_SPI_ADC
// Project Name: Saturn
// Target Devices: Artix 7
// Tool Versions: Vivado
// Description: Reader for ADC78H90. Reads data into registers; peah hold for
//              forward/reverse power; axi4 read port.
//              clocked by AXI clock, not ADC clock
//
// Copyright 2022 Laurence Barker G8NJJ
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1 ns / 1 ps

module AXI_SPI_ADC #
(
  parameter integer AXI_DATA_WIDTH = 32,
  parameter integer AXI_ADDR_WIDTH = 16
)
(
  input wire aclk,
  input wire aresetn,
//
// SPI signals
//
  output reg nCS,				// ADC chip select
  output reg MOSI,				// serial output to ADC
  input wire MISO,				// serial input from ADC
  output reg SCLK,				// ADC serial clock
//
// AXI bus Slave 
//
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
  input  wire                      s_axi_rready   // AXI4-Lite slave: Read data ready
);
//
// local variables
//
// axi interface
  reg [AXI_ADDR_WIDTH-1:0] raddrreg;
  reg [AXI_DATA_WIDTH-1:0] rdatareg;
  reg arreadyreg;                          // false when write address has been latched
  reg rvalidreg;                           // true when read data out is valid

  reg[1:0] clk_divide;				       // derive input clock/4 (31.25MHz)
  reg[1:0] clk_phase;				       // derive input clock/16 as 4 phases (7.8125MHz)

// internal storage registers for ADC results
  reg [11:0] AIN1; // 
  reg [11:0] AIN2; // 
  reg [11:0] AIN3; // 
  reg [11:0] AIN4; // 
  reg [11:0] AIN5; // holds VFWD volts
  reg [11:0] AIN6; // holds 13.8v supply voltage

// internal registers for SPI shift
  reg  [2:0] ADCAddress;			        // current register address
  reg  [2:0] NextADCAddress;                // next ADC address			
  reg  [15:0] ADCData;				        // shifted data
  reg   [4:0] BitCnt;				        // bit counter in shift sequence
 
// internal registers. When set, clear AIN1 or AIN2
  reg clear_AIN1;                       // asserted by AXI read block to clear a peak hold reg when next accessed
  reg clear_AIN2;
  reg release_clear_AIN1;               // signal to AXI red block
  reg release_clear_AIN2;

//
// generate 31.25MHz clock and 7.8125MHz clock
//
  always @ (posedge aclk)
  if(~aresetn)
  begin
    clk_divide = 2'b00;                 // reset to 0
    clk_phase = 2'b00;                  // reset to 0
  end
  else
  begin
    if(clk_divide == 2'b11)             // if count =3, reset to 0
    begin
      clk_divide <= 2'b00;
      // move clock phase to next state
      if(clk_phase == 2'b11)
      begin
        clk_phase <= 2'b00;
      end
      else
      begin
        clk_phase <= (clk_phase + 1);   // else increment count
      end
    end
    else
    begin
      clk_divide <= (clk_divide + 1);   // else increment count
    end
  end

//
// clock SPI data
//
  always @ (posedge aclk)
  if(~aresetn)
  begin
    BitCnt <= 5'b000;                   // reset to 0
	ADCAddress <= 3'b101;		        // reset current ADC address
	NextADCAddress <= 3'b000;		    // reset ADC address
	ADCData <= 16'b0;                   // shift register
	release_clear_AIN1 <= 0;            // don't clear
	release_clear_AIN2 <= 0;
	AIN1 <= 0;
	AIN2 <= 0;
	AIN3 <= 0;
	AIN4 <= 0;
	AIN5 <= 0;
	AIN6 <= 0;
  end
  //
  // do erase on alternate ticks (every 4th clock, but out of phase with main code)
  //
  else if (clk_divide == 2'b10)         // else every 4th clock
  begin
    if(clear_AIN1)
    begin
      AIN1 <= 0;
      release_clear_AIN1 <= 1;
    end

    if(clear_AIN2)
    begin
      AIN2 <= 0;
      release_clear_AIN2 <= 1;
    end
    // if we have signalled for a "clear" bit to be released, remove the signal now
    // (so this bit is  asserted for 4 clock cycles)
    if(release_clear_AIN1 == 1)
      release_clear_AIN1 <= 0;
    if(release_clear_AIN2 == 1)
      release_clear_AIN2 <= 0;
  end
  //
  // main shifting code
  //
  else if (clk_divide == 2'b00)         // else every 4th clock
  begin
    case (clk_phase)
    0:  begin
            if(BitCnt == 5'b00000)               //clear data register
            begin
                ADCData <= 16'b0;                   // shift register
                nCS <= 0;                           // asset chip select
            end
            else if(BitCnt == 5'b10000)             // deassert CS in last state
            begin
                nCS <= 1;
                // now save ADC data to correct register
                case (ADCAddress)          // save shifted data to register
                    0:	if(ADCData > AIN1)
                        AIN1 <= ADCData;        // peak hold, unless peak cleared
                    1:	if(ADCData > AIN2)
                        AIN2 <= ADCData;        // peak hold, unless peak cleared
                    2: 	AIN3 <= ADCData;   	    // capture incoming data
                    3:	AIN4 <= ADCData;
                    4:	AIN5 <= ADCData;
                    5:	AIN6 <= ADCData;
                endcase	
                
            end
        end                             
    
    1:  begin
            SCLK <= 0;                  // clock toggle
            if(BitCnt == 5'b00010)      // MISO 1st o/p bit
                MOSI <= NextADCAddress[2];
            else if(BitCnt == 5'b00011)      // MISO 2nd o/p bit
                MOSI <= NextADCAddress[1];
            else if(BitCnt == 5'b00100)      // MISO 3rd o/p bit
                MOSI <= NextADCAddress[0];
        end
    
    2:  begin
            if(BitCnt == 16)            // increment ADC address
            begin
                ADCAddress <= NextADCAddress;
                if(NextADCAddress >= 5)
                    NextADCAddress <= 0;
                else
                    NextADCAddress <= NextADCAddress + 1;
            end
        end
    
    3:  begin
            SCLK <= 1;                  // clock toggle
            // shift data; only add MOSI after 4 zero bits
            if(BitCnt <= 15)
            begin
                ADCData[15:1] <= ADCData[14:0];
                if(BitCnt >= 4)
                    ADCData[0] <= MISO;
                else
                    ADCData[0] <= 0;
            end
            
            if(BitCnt != 5'b10000)      // advance bit count
                BitCnt <= BitCnt+1;
            else
                BitCnt <= 0;    
        end
    
    endcase
  end 


//
// AXI-4 read strategy:
// 1. at reset, assert arready and tready, to be able to accept address and stream transfers 
// 2. when arvalid is true, signalling address transfer, deassert arready
// 3. after address cyclewhen arready is false: assert rvalid, and present data  
// 4. when rvalid and rready both true, data is transferred:
// 4a. reassert arready
//

  assign s_axi_rdata = rdatareg;
  assign s_axi_arready = arreadyreg;
  assign s_axi_rvalid = rvalidreg;

  always @(posedge aclk)
  begin
    if(~aresetn)
    begin
// step 1
      raddrreg <= {(AXI_ADDR_WIDTH){1'b0}};
      rdatareg <= {(AXI_DATA_WIDTH){1'b0}};
      arreadyreg <= 1'b1;                           // ready for address transfer
      rvalidreg <= 1'b0;                            // not ready to transfer read data
      clear_AIN1 <= 0;
	  clear_AIN2 <= 0;
    end
    else
    begin
    
    if(release_clear_AIN1 == 1)
      clear_AIN1 <= 0;
    if(release_clear_AIN2 == 1)
      clear_AIN2 <= 0;
    
// step 2. read address transaction: latch when arvalid and arready both true    
      if(s_axi_arvalid & arreadyreg)
      begin
        raddrreg <= s_axi_araddr;               // latch the read address
        arreadyreg <= 1'b0;                     // clear when address transaction happens
      end
// step 3. assert rvalid and data when address and stream data transfers are ready
      if(!arreadyreg)                           // address already complete
      begin
        rvalidreg <= 1'b1;                                  // signal ready to complete data
        case(raddrreg[4:2])                                 // select appropriate register
          0: rdatareg <= AIN1;
          1: rdatareg <= AIN2;
          2: rdatareg <= AIN3;
          3: rdatareg <= AIN4;
          4: rdatareg <= AIN5;
          5: rdatareg <= AIN6;
          default: rdatareg <= 0;
        endcase
      end
// step 4. When rvalid and rready, terminate the transaction & clear data. 
// if read of AIN1 or AIN2, clear the "peak held" value
      if(rvalidreg & s_axi_rready)
      begin
        rvalidreg <= 1'b0;                                  // deassert rvalid
        arreadyreg <= 1'b1;                                 // ready for new address
        rdatareg <= {(AXI_DATA_WIDTH){1'b0}};
        case(raddrreg[4:2])                                 // select appropriate register
          0: clear_AIN1 <= 1;
          1: clear_AIN2 <= 1;
        endcase
      end
    end
  end

// drive output from registered internals
  assign s_axi_arready = arreadyreg;
  assign s_axi_rdata = rdatareg;
  assign s_axi_rvalid = rvalidreg;
  assign s_axi_rresp = 2'd0;
// and outputs to make sure we don't respond to a write
  assign s_axi_bresp = 2'd0;                         // no response to write access
  assign s_axi_awready = 1'b0;                       // no response to write access
  assign s_axi_wready = 1'b0;                        // no response to write access
  assign s_axi_bvalid = 1'b0;                        // no response to write access


endmodule