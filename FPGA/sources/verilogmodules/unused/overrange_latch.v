
`timescale 1 ns / 1 ps
//////////////////////////////////////////////////////////////////////////////////
// Company: HPSDR
// Engineer: Laurence Bsarker G8NJJ
// 
// Create Date: 24.11.2018 10:24:28
// Design Name: 
// Module Name: overrange_latch
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// latch the LTC2208 ADC overrange indication
// and hold until cleared
//
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module overrange_latch 
(
  // System signals
    input wire arstn,                   // asynch reset
    input  wire aclk,					// ADC clock
    input wire overrange,				// ADC overrange input
    input wire clear,					// active high "clear"
	output reg overrange_latched 
);

always @ (posedge aclk)
begin
    if (!arstn)
    begin
        overrange_latched  <= 0;          // reset sequencer
    end
    else                                // not reset - normal operation
    begin
	if (overrange == 1)
		overrange_latched <= 1;
	else if (clear == 1)
		overrange_latched <= 0;
	end
end

endmodule
