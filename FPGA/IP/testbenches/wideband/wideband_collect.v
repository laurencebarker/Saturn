//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    21/9/2024
// Design Name:    Wideband Collect
// Module Name:    Wideband_Collect
// Project Name:   Saturn 
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    Module to record wideband sample batches to a FIFO.
//                 Record 4K-16K of ADC0 or ADC1 samples to a FIFO; then record next 
//		   after FIFO read out.
//                 Allow readback of FIFO current depth and recording state
//                 AXI4-Lite bus interface to processor 
// Registers:
//  addr 0         Control. R/W. Bit0=1: enable ADC0; bit1=1: enable ADC1 bit2: 1 to indicate data has been read
//  addr 4         RecordPeriod. R/W.  Period in clock ticks between restart of recording 
//  addr 8         Depth. R/W. Number of 64 bit words to be recorded into FIFO from one ADC, minus one
//                 (to record 1024 words, write 1023)
//  addr C         Status. R. 
//	bit 13:90) FIFO depth in 64 bit words. 
//	bit 31	   ADC1 data ready. 1 if data available to read.
//	Bit 30	   ADC0 data ready. 1 if data available to read.
//
// FIFO Interface signals:
//	AXI stream:   	FIFO data to record
//	Count:		current FIFO depth, in words
//
// ADC interfaces:
//	ADC0(15:0)	continuous (not stream) data for ADC0
//	ADC1(15:0)	continuous (not stream) data for ADC1
//
// This IP clocked at 122.88MHz: same clock domain as ADCs


// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1 ns / 1 ps

module Wideband_Collect #
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
  // AXI stream output
  //
  output reg [63:0]               m_axis_tdata,   // AXI stream data to FIFO
  output reg                      m_axis_tvalid,  //AXI stream enable signal

  output reg                      startrecord,    // debug strobe set when recording starts

  //
  // FIFO interface 
  // note the Xilinx FIFO reports the number of words held through both read and write side
  //
  input wire [31:0]                fifo_count,    // current number of words in FIFO

// ADC interface
  input wire [15:0]                adc0,
  input wire [15:0]                adc1
);


//
// AXI registers
//
  reg [31:0] controlreg; 		    // writable register - control register
  reg [31:0] recordperiodreg; 		    // writable register - record period register
  reg [31:0] depthreg; 		    	    // writable register - depth register
  reg [1:0] dataavailablereg;		    // data available when set (by WB state machine)
  reg controlregwritten;		    // set when control register has been written 
  reg DataReadOut;			               // set true when processor has read the data
                                           // each is SR flip flop: set by processor write, cleared by record.
  reg [31:0] delaycountreg;		           // inter-record delay, in ticks
  reg [31:0] samplecountreg;               // sample count during record
  reg [3:0] wbstatereg;                    // state machine state

//
// AXI interface
//
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
      rdatareg <= {(AXI_DATA_WIDTH){1'b0}};
      arreadyreg <= 1'b1;                           // ready for address transfer
      rvalidreg <= 1'b0;                            // not ready to transfer read data
      awreadyreg  <= 1'b1;                          // initialise to write address ready
      wreadyreg  <= 1'b1;                           // initialise to write data ready
      bvalidreg <= 1'b0;                            // initialise to "not ready to complete"
// clear the wideband control registers      
      controlreg <= 32'h0; 		    	    // writable register - control register
      recordperiodreg <= 32'h0; 		    // writable register - record period register
      depthreg <= 32'h0; 		    	    // writable register - depth register

    end
    else
    begin

      controlregwritten <= 0;                       // ordinarily, clear this bit
//
// implement read transactions
// read step 2. read address transaction: latch when arvalid and arready both true    
      if(s_axi_arvalid & arreadyreg)
      begin
        arreadyreg <= 1'b0;                  // clear when address transaction happens
        raddrreg <= s_axi_araddr;            // latch read address
      end
// read step 3. assert rvalid & data when address is complete
// data is picked from one of 4 readable registers based on the address presented
      if(!arreadyreg)         // address complete
      begin
        rvalidreg <= 1'b1;                                  // signal ready to complete data
        case (raddrreg[3:2])
        0:  rdatareg <= controlreg;                        // concat data
        1:  rdatareg <= recordperiodreg;                        // concat data
        2:  rdatareg <= depthreg;                        // concat data
        3:  rdatareg <= {dataavailablereg[1:0], fifo_count[29:0]};                        // concat data
        endcase
      end
// read step 4. When rvalid and rready, terminate the transaction.
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
        case (waddrreg[3:2])
          0: begin
               controlreg <= wdatareg;      // write 32 bits
	           controlregwritten <= 1;                      // set for one cycle on control reg write
             end
          1: begin
               recordperiodreg <= wdatareg;      // write 32 bits
             end
          2: begin
               depthreg <= wdatareg;      // write 32 bits
             end
          3: begin				// no action for write to status register
             end
        endcase
      end 

    end         // if(!aresetn)
  end           // always @

//
// now code for wideband recording
//
  always @(posedge aclk)
  begin
    if(~aresetn)
    begin
// reset to start states
      DataReadOut <= 1'b0;				// clear the enable bits
      dataavailablereg <= 2'b00;                        // no data available to read
      m_axis_tdata <= 0;
      m_axis_tvalid <= 0;
      startrecord <= 0;
      delaycountreg <= 0;
      samplecountreg <= 0;
      wbstatereg <= 0;
    end
    else
    begin

      // if control reg written to in last cycle, latch the enable bits
      if(controlregwritten)
        DataReadOut <= controlreg[2];

      // in any active state, decrement the delay counter until it reaches zero; then hold it there
      if(wbstatereg[3:0] != 0)
	    if(delaycountreg != 0)
          delaycountreg <= delaycountreg - 1;

	// now a state machine for recording control:
        case (wbstatereg[3:0])
          0: begin				// idle state
	        dataavailablereg[1:0] <= 2'b00;        // clear available data
	        if(controlreg[0] == 1'b1)		// if ADC0 enabled
	        begin
		      wbstatereg <= 1;
		      delaycountreg <= recordperiodreg;
	          startrecord <= 1;
	        end
	        else if(controlreg[1] == 1'b01)	// else if ADC1 enabled
	        begin
              wbstatereg <= 9;
	          delaycountreg <= recordperiodreg;
	          startrecord <= 1;
	        end
          end

          1: begin				// begin ADC0
	        dataavailablereg[1:0] <= 2'b00;
	        startrecord <= 0;
	        wbstatereg <= 2;
	        samplecountreg <= depthreg;
          end

          2: begin				// record 1 ADC0
	        m_axis_tdata[15:0] <= adc0[15:0];
	        m_axis_tvalid <= 0;
	        wbstatereg <= 3;
          end
          
          3: begin				// record 2 ADC0
	        m_axis_tdata[31:16] <= adc0[15:0];
	        wbstatereg <= 4;
          end

          4: begin				// record 3 ADC0
	        m_axis_tdata[47:32] <= adc0[15:0];
	        wbstatereg <= 5;
          end

          5: begin				// record 4 ADC0
	        m_axis_tdata[63:48] <= adc0[15:0];
	        m_axis_tvalid <= 1;			// write out 64 bits
	        if(samplecountreg == 0)
	        begin
	          wbstatereg <= 6;
	        end
	        else
	        begin
	          samplecountreg <= samplecountreg - 1;
	          wbstatereg <= 2;
	        end
          end

          6: begin				// finish ADC0
	        m_axis_tvalid <= 0;
	        dataavailablereg[0] <= 1;
	        DataReadOut <= 0;          // clear state so we can detect new processor write
	        wbstatereg <= 7;
          end

          7: begin				// wait after record ADC0: needs processor to read data & acknowledge
            if(controlreg[1:0] == 2'b00)		// if disabled
              wbstatereg <= 0;            
            else if (DataReadOut == 1'b1)                // wait for processor action
            begin
    	      if(controlreg[1] == 1'b1)	// if re-enabled by processor && ADC1 enabled
	          begin
	            wbstatereg <= 9;
	            startrecord <= 1;
	          end
	          else 
	            wbstatereg <= 8;
	        end
          end

          8: begin				// wait for timeout
	        dataavailablereg[1:0] <= 2'b00;
            if((controlreg[1:0] == 2'b00) || (delaycountreg == 0))		// if disabled
              wbstatereg <= 0;            
          end

          9: begin				// begin ADC1
	        dataavailablereg[1:0] <= 2'b00;
	        startrecord <= 0;
	        wbstatereg <= 10;
	        samplecountreg <= depthreg;
          end

          10: begin				// record 1 ADC1
	        m_axis_tdata[15:0] <= adc1[15:0];
	        m_axis_tvalid <= 0;
	        wbstatereg <= 11;
          end

          11: begin				// record 2 ADC1
	        m_axis_tdata[31:16] <= adc1[15:0];
	        wbstatereg <= 12;
          end

          12: begin				// record 3 ADC1
	        m_axis_tdata[47:32] <= adc1[15:0];
	        wbstatereg <= 13;
          end

          13: begin				// record 4 ADC1
	        m_axis_tdata[63:48] <= adc1[15:0];
	        m_axis_tvalid <= 1;			// write out 64 bits
	        if(samplecountreg == 0)
	        begin
	          wbstatereg <= 14;
	        end
	        else
	        begin
	          samplecountreg <= samplecountreg - 1;
	          wbstatereg <= 10;
	        end
          end

          14: begin				// finish ADC1
	        m_axis_tvalid <= 0;
	        dataavailablereg[1] <= 1;
	        DataReadOut <= 0;          // clear state so we can detect new processor write
	        wbstatereg <= 15;
          end

          15: begin				// wait after record ADC1
            if(controlreg[1:0] == 2'b00)		// if disabled
              wbstatereg <= 0;            
	        else if(DataReadOut == 1)		// if re-enabled by processor
	          wbstatereg <= 8;
            end
        endcase
    end         // if(!aresetn)
  end           // always @

endmodule