
`timescale 1 ns / 1 ps
//////////////////////////////////////////////////////////////////////////////////
// Company: HPSDR
// Engineer: Laurence Bsarker G8NJJ
// 
// Create Date: 03.06.2021 17:20:00
// Design Name: 
// Module Name: AXILite_Alex_SPI
// Project Name: Saturn
// Target Devices: Artix 7
// Tool Versions: 
// Description: 
// AXILite bus interface to RF SPI Alex interface
//
// Registers:
//  addr 0         TX filter & RX antenna Data (bits 15:0)
//  addr 4         RX data (bits 31:0)
//  addr 8:        TX filter & TX antenna data (bits 156:0)

// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
// revision 1.0: changed to do initial shift at the sTART of reset, not after released
// revision 1.1: 2nd 16 bit register to hold the settings shifted if TX is asserted; 
//               1st register (addr 0) holds the settings used for RX
//               for backward compatibility: if TX ant bits don't contain a 1, load 
//               the same data as used for RX ( this means older thetis/piHPSDR will work) 
// 
// Modified from original Alex interface code
// Copyright 2006,2007 Phil Harman VK6APH
//  HPSDR - High Performance Software Defined Radio
//////////////////////////////////////////////////////////////////////////////////

//	data to send to Alex Tx filters is in the following format:
//	Bit  0 - NC				U3 - D0
//	Bit  1 - NC				U3 - D1
//	Bit  2 - txrx_status    U3 - D2
//	Bit  3 - Yellow Led		U3 - D3
//	Bit  4 - 30/20m	LPF		U3 - D4
//	Bit  5 - 60/40m	LPF		U3 - D5
//	Bit  6 - 80m LPF		U3 - D6
//	Bit  7 - 160m LPF    	U3 - D7
//	Bit  8 - Ant #1			U5 - D0
//	Bit  9 - Ant #2			U5 - D1
//	Bit 10 - Ant #3			U5 - D2
//	Bit 11 - T/R relay		U5 - D3
//	Bit 12 - Red Led		U5 - D4
//	Bit 13 - 6m	LPF			U5 - D5
//	Bit 14 - 12/10m LPF		U5 - D6
//	Bit 15 - 17/15m	LPF		U5 - D7
// bit 4 (or bit 11 as sent by AXI) replaced by TX strobe

//	data to send to Alex Rx filters is in the folowing format:
//  bits 15:0 - RX1; bits 31:16 - RX1
// (IC designators and functions for 7000DLE RF board)
//	Bit  0 - Yellow LED 	  U6 - QA
//	Bit  1 - 10-22 MHz BPF 	  U6 - QB
//	Bit  2 - 22-35 MHz BPF 	  U6 - QC
//	Bit  3 - 6M Preamp    	  U6 - QD
//	Bit  4 - 6-10MHz BPF	  U6 - QE
//	Bit  5 - 2.5-6 MHz BPF 	  U6 - QF
//	Bit  6 - 1-2.5 MHz BPF 	  U6 - QG
//	Bit  7 - N/A      		  U6 - QH
//	Bit  8 - Transverter 	  U10 - QA
//	Bit  9 - Ext1 In      	  U10 - QB
//	Bit 10 - N/A         	  U10 - QC
//	Bit 11 - PS sample select U10 - QD
//	Bit 12 - RX1 Filt bypass  U10 - QE
//	Bit 13 - N/A 		      U10 - QF
//	Bit 14 - RX1 master in	  U10 - QG
//	Bit 15 - RED LED 	      U10 - QH
//	Bit 16 - Yellow LED 	  U7 - QA
//	Bit 17 - 10-22 MHz BPF 	  U7 - QB
//	Bit 18 - 22-35 MHz BPF 	  U7 - QC
//	Bit 19 - 6M Preamp    	  U7 - QD
//	Bit 20 - 6-10MHz BPF	  U7 - QE
//	Bit 21 - 2.5-6 MHz BPF 	  U7 - QF
//	Bit 22 - 1-2.5 MHz BPF 	  U7 - QG
//	Bit 23 - N/A      		  U7 - QH
//	Bit 24 - Transverter 	  U13 - QA
//	Bit 25 - Ext1 In      	  U13 - QB
//	Bit 26 - N/A         	  U13 - QC
//	Bit 27 - PS sample select U13 - QD
//	Bit 28 - RX1 Filt bypass  U13 - QE
//	Bit 29 - N/A 		      U13 - QF
//	Bit 30 - RX1 master in	  U13 - QG
//	Bit 31 - RED LED 	      U13 - QH
	
//	SPI data is sent to Alex whenever an AXI-Lite write occurs,
// or T/R strobe changes

module AXILite_Alex_SPI #
(
  parameter integer AXI_DATA_WIDTH = 32,
  parameter integer AXI_ADDR_WIDTH = 16,
  parameter integer CLOCK_DIVIDER = 12
)

(
  input wire aclk,                              // AXI clock
  input wire aresetn,                           // AXI reset

  output reg SPI_data,                          // SPI data to Alex
  output reg SPI_ck,                         // SPI clock to Alex
  output reg Rx_load_strobe,                    // latch strobe for RX data
  output reg Tx_load_strobe,                    // latch strobe for TX data
  input wire TX_Strobe,                         // TX/RX strobe; shifts out as TX data bit 11
  
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
  reg[15:0] DivideCount;		// clock divide count register

  reg [3:0]spi_state = 4'b0000;
  reg [5:0]data_count;
  reg [31:0]previous_Rx_data;	// used to detect change in data
  reg [15:0]previous_Tx_data;	// used to detect change in data
  reg [31:0]shiftregister;	// data being shifted
  reg tx_needed = 0;          	// flag true if tx data shift needed
  reg rx_needed = 0;          	// true if rx shift required
  reg shifting_rx = 0;        	// true if currently shifting RX data   

  reg [AXI_ADDR_WIDTH-1:0] raddrreg;        // AXI read address register
  reg [AXI_ADDR_WIDTH-1:0] waddrreg;        // AXI write address register
  reg [AXI_DATA_WIDTH-1:0] axiTXdatareg;    // TX filter/RX ant shift data register
  reg [AXI_DATA_WIDTH-1:0] axiTXdatareg2;   // TX filter & ant shift data register
  reg [AXI_DATA_WIDTH-1:0] TXdatareg;       // TX shift data register, with TX strobe
  reg [AXI_DATA_WIDTH-1:0] axiRXdatareg;    // RX shift data register
  reg [AXI_DATA_WIDTH-1:0] rdatareg;        // AXI data register
  reg [AXI_DATA_WIDTH-1:0] wdatareg;        // AXI data register
  reg arreadyreg;                           // false when write address has been latched
  reg rvalidreg;                            // true when read data out is valid
  reg awreadyreg;                           // false when write address has been latched
  reg wreadyreg;                            // false when write data has been latched
  reg bvalidreg;                            // goes true when address and data completed
  reg prev_aresetn = 1;                     // previous state of aresetn 
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

//
// clock divider
//
  always @ (posedge aclk)
    begin
      if (!aresetn)
	    DivideCount <= 0;
      else if (DivideCount == 0)
	    DivideCount <= (CLOCK_DIVIDER-1);
      else
	    DivideCount <= DivideCount - 1'b1;
    end


//
// Alex data shifter
//
  always @ (posedge aclk)
  begin
    prev_aresetn <= aresetn;                 // store state
// on the first cycle of reset, initialise states and force a shift of both RX and TX data
    if (prev_aresetn && !aresetn)
    begin
        rx_needed <= 1;                          // TX and RX both to be shifted with zeros
        tx_needed <= 1;
        previous_Rx_data <= 32'h00000000;
        previous_Tx_data <= 16'h0000;
        spi_state <= 0;                         // initial sequencer state
        TXdatareg <= 0;
        Tx_load_strobe <= 0;
        Rx_load_strobe <= 0;
        SPI_data <= 0;
        SPI_ck <= 0;
    end
    else if(DivideCount == 0)                       // only process every N clocks
    begin

//
// first see if RX data or TX data have changed
// RX data is shifted from the AXI register data
// ant  TX filter data needs bit 11 replaced by TX strobe input  & choose the TX or RX version
//
        if(TX_Strobe == 1)
            TXdatareg <= {axiTXdatareg2[31:12], TX_Strobe, axiTXdatareg2[10:0]};
        else
            TXdatareg <= {axiTXdatareg[31:12], TX_Strobe, axiTXdatareg[10:0]};

        if (axiRXdatareg != previous_Rx_data)
        begin
            //previous_Rx_data <= axiRXdatareg;  set later
            rx_needed <= 1;
        end
        
        if (TXdatareg != previous_Tx_data)
        begin
            //previous_Tx_data <= TXdatareg;
            tx_needed <= 1;
        end
    
    //
    // now the sequencer acts on the tx or rx needed flags
    //
        case (spi_state)
        0:	begin                                    // idle state - see if triggered to start
                if (tx_needed)
                begin
                    data_count <= 15;
                    shifting_rx <= 0;
                    tx_needed <= 0;                 // clear now so new data can be registered
                    shiftregister[31:16] <= TXdatareg[15:0]; 
                    previous_Tx_data[15:0] <= TXdatareg[15:0];
                    spi_state <= 1;
                end
                else if (rx_needed)
                begin
                    data_count <= 31;
                    shifting_rx <= 1;
                    rx_needed <= 0;                 // clear now so new data can be registered
                    shiftregister[31:0] <= axiRXdatareg[31:0]; 
                    previous_Rx_data[31:0] <= axiRXdatareg[31:0];
                    spi_state <= 1;
                end
                else spi_state <= 0; 			      // wait for trigger
            end		
        
        1:	begin                                    // assert data bit
               SPI_data <= shiftregister[31];	        // shift a bit
               shiftregister <= shiftregister << 1;
               spi_state <= 2;
            end
        
        2:	begin
               SPI_ck <= 1'b1;					// set clock high
               spi_state <= 3;
            end
        
        3:	begin
               SPI_ck <= 1'b0;					// set clock low
               spi_state <= 4;
            end
        
        4:	begin                                // see if end of shift
                if(data_count == 0) begin
                    if (shifting_rx)                // assertt a strobe & clear "shift needed
                    begin
                        Rx_load_strobe <= 1'b1;
                        spi_state <= 5;
                    end
                    else
                    begin
                        Tx_load_strobe <= 1'b1;
                        spi_state <= 5;
                    end	       	
                end 
                else
                begin
                    data_count <= data_count - 1'b1;
                    spi_state <= 1;
                end
            end
            
        5:	begin
               Tx_load_strobe <= 1'b0;				// reset Tx strobe
               Rx_load_strobe <= 1'b0;				// reset Rx strobe
               spi_state <= 0;						// now do Rx data
            end
            
        default: begin
                    spi_state <= 0;						// initial state   
                 end
        endcase
    end
  end    

//
// AXI4 Lite transactions
//
  always @ (posedge aclk)
  if(!aresetn)				// if reset
    begin
      axiTXdatareg <= {(AXI_DATA_WIDTH){1'b0}};
      axiTXdatareg2 <= {(AXI_DATA_WIDTH){1'b0}};
      axiRXdatareg <= {(AXI_DATA_WIDTH){1'b0}};
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

        case(raddrreg[3:2])
          0: rdatareg <= axiTXdatareg;
          1: rdatareg <= axiRXdatareg;
          2: rdatareg <= axiTXdatareg2;
          3: rdatareg <= axiTXdatareg2;
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

        case(waddrreg[3:2])
          0: axiTXdatareg <= wdatareg;
          1: axiRXdatareg <= wdatareg;
          2: axiTXdatareg2 <= wdatareg;
          3: axiTXdatareg2 <= wdatareg;
        endcase 
      end 
    end


endmodule
