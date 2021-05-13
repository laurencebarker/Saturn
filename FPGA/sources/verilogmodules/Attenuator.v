//
//  HPSDR - High Performance Software Defined Radio
//
//  Hermes code. 
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


//  Serial Attenuator driver - 2014  (C) Phil Harman VK6APH

//  Driver for Minicircuits DAT-33-SP+ attenuator
//  C16 set = 16dB, C8 set = 8dB etc

//
// NOTE: CLK is a max of 10MHz

/*


			    +--+  +--+  +--+  +--+  +--+  +--+  
CLK 	    ---+  +--+  +--+  +--+  +--+  +--+  +----
                >  < 30nS min      
											   >||< 10nS min
			   +-----+-----+-----+-----+-----+
DATA        | C16 | C8  | C4  | C2  | C1  |
			   +-----+-----+-----+-----+-----+--------------------
			  MSB                          LSB                                     
			                                        +--+
LE          -------------------------------------+  +----------
											           >  < 30nS min

The register data is latched once LE goes high. 


*/

module SerialAtten (aclk, ce_n, data, resetn, ATTN_CLK, ATTN_DATA, ATTN_LE);

(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK" *)
(* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET resetn" *)
input wire aclk;							// CLK - 10MHz or less
input wire ce_n;                        // clock enable - low to clock

(* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 resetn RST" *)
(* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
input wire resetn;                        // active low reset
input wire [4:0] data;		            // Attenuator setting 
(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ATTN_CLK CLK" *)
(* X_INTERFACE_PARAMETER = "FREQ_HZ 10000000" *)
output reg ATTN_CLK = 0;				// clock to attenuator chip - max 10MHz 
output reg ATTN_DATA = 0;				// data to attenuator chip
output reg ATTN_LE = 0;					// data latch to attenuator chip]

reg [2:0] bit_count = 0;
reg [5:0] shiftreg = 0;
reg [3:0] state = 0;
reg [5:0] previous_data = 0;

always @ (posedge aclk)
if (!resetn)
begin
  state <= 0; 
end 
else if (!ce_n)
begin

case (state)

0: begin 
   bit_count <= 6;
   previous_data <= data;				// save current attenuator data in case it changes whilst we are
   shiftreg[5:1] <= data[4:0];
   shiftreg[0] <= 0; 
   state <= state + 1'b1;				// send data
   end 

1:	begin                                // set data bit
	ATTN_DATA <= shiftreg[5];
	shiftreg <= shiftreg << 1;
	state <= state + 1'b1;
	end
	
// clock data out, set clock high  
2:  begin 
	bit_count <= bit_count - 1'b1;
	ATTN_CLK <= 1'b1;
	state <= state + 1'b1;
	end 
	
// set clock low	
3:	begin
	ATTN_CLK <= 0;
		if (bit_count == 0) begin		// all data sent? If so send latch signal
			state <= state + 1'b1;
		end 
		else state <= 1;				// more bits to send
	end
	 
// delay before we send the LE as required by the attenuator chip	
4:	begin
	ATTN_LE <= 1'b1;
	state <= state + 1'b1;
	end

// reset LE pulse and wait until data changes	
5:	begin
	ATTN_LE <= 0;
		if (data != previous_data) begin  // loop here until data changes
			state <= 0;
		end
	end 
	
endcase
end 

endmodule

