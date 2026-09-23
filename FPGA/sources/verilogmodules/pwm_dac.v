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


//
// pwmdac.v from Orion code (C) Phil Harman VK6APH
// provides 8 bit equivalent DAC output by PWM a digital output pin.
// PWM_count increments using 122.88MHz clock. If the count is less than
// the desired value then output will be high, otherwise low.
//
module PWM_DAC (aclk, PWM_source, DAC_bit);

(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK" *)
input wire aclk;				// 122.88MHz clock
input wire [7:0] PWM_source;	// input value = desired analogue
output reg DAC_bit = 0;		// output value

reg [7:0] PWM_count = 0;


// the count runs 0..254 (period 255 clocks) and the output is high while
// PWM_source > count, so 0 gives 0% duty and 255 gives 100% duty.
// (previously 0 still gave a 1/256 duty cycle, a small residual output)
always @ (posedge aclk)
begin 
	if (PWM_count == 8'd254)
		PWM_count <= 0;
	else
		PWM_count <= PWM_count + 1'b1;
	if (PWM_source > PWM_count)
		DAC_bit <= 1'b1;
	else 
		DAC_bit <= 1'b0;
end 

endmodule