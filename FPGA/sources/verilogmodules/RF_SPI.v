// V1.0 25th October 2007
//
// Copyright 2006,2007 Phil Harman VK6APH
//
//  HPSDR - High Performance Software Defined Radio
//
//  RF SPI interface.
//
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

// modified Laurence Barker G8NJJ for new project

//////////////////////////////////////////////////////////////
//
//		RF SPI interface
//
//////////////////////////////////////////////////////////////

/*
	data to send to Alex Tx filters is in the following format:

	Bit 15 - NC					U2 - D0
	Bit 14 - NC					U2 - D1
	Bit 13 - NC					U2 - D2
	Bit 12 - Yellow Led		U2 - D3
	Bit 11 - 30/20m			U2 - D4
	Bit 10 - 60/40m			U2 - D5
	Bit  9 - 80m				U2 - D6
	Bit  8 - 160m				U2 - D7

	Bit  7 - Ant #1			U4 - D0
	Bit  6 - Ant #2			U4 - D1
	Bit  5 - Ant #3			U4 - D2
	Bit  4 - T/R relay		U4 - D3
	Bit  3 - Red Led			U4 - D4
	Bit  2 - 6m					U4 - D5
	Bit  1 - 12/10m			U4 - D6
	Bit  0 - 17/15m			U4 - D7

	Relay selection data is contained in [6:0]LPF
	
	data to send to Alex Rx filters is in the folowing format:
	

	Bit 15 - RED LED 			U28 - QA
	Bit 14 - 1.5 MHz HPF 	U28 - QB
	Bit 13 - 6.5 MHz HPF 	U28 - QC
	Bit 12 - 9.5 MHz HPF 	U28 - QD
	Bit 11 - 6M Preamp 		U28 - QE
	Bit 10 - 13 MHz HPF 		U28 - QF
	Bit 09 - 20 MHz HPF 		U28 - QG
	Bit 08 - Bypass 			U28 - QH
	Bit 07 - 10 dB Atten. 	U30 - QA
	Bit 06 - 20 dB Atten. 	U30 - QB
	Bit 05 - Transverter	RX U30 - QC
	Bit 04 - RX 2 In 			U30 - QD
	Bit 03 - RX 1 In 			U30 - QE
	Bit 02 - RX 1 OUT 		U30 - QF Low = Default Receive Path
	Bit 01 - N.C.				U30 - QG
	Bit 00 - YELLOW LED 		U30 - QH
	
	Relay selection data is contained in [5:0]HPF
	All outputs are active high

	SPI data is sent to Alex whenever any of the above data changes

*/

module SPI(aclk, ce_n, resetn, Rx_data, Tx_data, SPI_data, SPI_clock, Rx_load_strobe, Tx_load_strobe);

(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK" *)
(* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET resetn" *)
input wire aclk;
(* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 resetn RST" *)
(* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
input wire resetn;                        // active low reset
input wire[31:0]Rx_data;                // 32 bit RX data for 2 ch
input wire[15:0]Tx_data;                // 16 bit TX datas
output reg SPI_data = 0;
(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 SPI_clock CLK" *)
(* X_INTERFACE_PARAMETER = "FREQ_HZ 10000000" *)
output reg SPI_clock = 0;
output reg Rx_load_strobe = 0;
output reg Tx_load_strobe = 0;
input wire ce_n;                        // active lowclock enable

reg [3:0]spi_state = 4'b0000;
reg [5:0]data_count;
reg [31:0]previous_Rx_data;	// used to detect change in data
reg [15:0]previous_Tx_data;	// used to detect change in data
reg [31:0]shiftregister;	// data being shifted
reg tx_needed = 0;          // flag true if tx data shift needed
reg rx_needed = 0;          // true if rx shift required
reg shifting_rx = 0;        // true if currently shifting RX data   

always @ (posedge aclk)
if(!ce_n)                       // only process if clock is enabled
begin

// on reset, initialise states and force a shify of both RX and TX data
    if (!resetn)
    begin
        rx_needed <= 1;                          // TX and RX both to be shifted with zeros
        tx_needed <= 1;
        previous_Rx_data <= 32'h00000000;
        previous_Tx_data <= 16'h0000;
        spi_state <= 0;                         // initial sequencer state
    end
    else                        // not reset; test if we need to shift new data
    begin
        if (Rx_data != previous_Rx_data)
        begin
            previous_Rx_data <= Rx_data;
            rx_needed <= 1;
        end
    
        if (Tx_data != previous_Tx_data)
        begin
            previous_Tx_data <= Tx_data;
            tx_needed <= 1;
        end
    end

//
// now the sequencer acts on the tx or rx needed flags
//
    case (spi_state)
    0:	begin                                    // idle state - see if triggered to start
            if (!resetn)
                spi_state <= 0;
            else if (tx_needed)
            begin
                data_count <= 15;
                shifting_rx <= 0;
                tx_needed <= 0;                 // clear now so new data can be registered
                shiftregister[31:16] <= Tx_data[15:0]; 
                spi_state <= 1;
            end
            else if (rx_needed)
            begin
                data_count <= 31;
                shifting_rx <= 1;
                rx_needed <= 0;                 // clear now so new data can be registered
                shiftregister[31:0] <= Rx_data[31:0]; 
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
           SPI_clock <= 1'b1;					// set clock high
           spi_state <= 3;
        end
    
    3:	begin
           SPI_clock <= 1'b0;					// set clock low
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

endmodule
