//////////////////////////////////////////////////////////////////////////////////
// Engineer: Laurence Barker G8NJJ 
// 
// Create Date: 23.10.2018 21:00:43
// Design Name: 
// Module Name: ClockDivider
// Target Devices: Zynq 7000
// Tool Versions: Vivado 2018.1
// Description: clock divider and terminal count generator
// 
// Dependencies: none 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

//ClockOut - clock divided by N value
// TC - terminal count indication; one clock cycle
// TCN - activie low terminal count
`timescale 1 ns/100 ps

module ClockDivider(aclk, resetn, ClockOut, TC, TCN);


parameter Divisor = 8;		// what to divide by
localparam NumBits = clogb2 (Divisor -1); // 0 to (Divisor -1)


(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK" *)
(* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET resetn" *)
input wire aclk;			// input clock

(* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 resetn RST" *)
(* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
input wire resetn;
(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ATTN_CLK CLK" *)
(* X_INTERFACE_PARAMETER = "FREQ_HZ 65000000" *)
output reg ClockOut;
output reg TC;
output reg TCN;		// registered output

reg[NumBits-1:0] Count;		// count register


//
// execute a simple sequence, counting down from (divisor-1) to 0
//
always @ (posedge aclk)
begin
	if (!resetn)
		Count <= 0;
	else if (Count == 0)
		Count <= (Divisor-1);
	else
		Count <= Count - 1'b1;


// now do the "D input" logic for terminal count and clock out
	if (Count == 1'b0)
	begin
		TC <= 1'b1;		// assert TC, TCN
		TCN <= 1'b0;
	end
	else
	begin
		TC <= 1'b0;		// deassert TC, TCN
		TCN <= 1'b1;
	end
	ClockOut <= (Count < Divisor/2)?1'b0:1'b1;
end

function integer clogb2;
input [31:0] depth;
begin
  for(clogb2=0; depth>0; clogb2=clogb2+1)
  depth = depth >> 1;
end
endfunction


endmodule
