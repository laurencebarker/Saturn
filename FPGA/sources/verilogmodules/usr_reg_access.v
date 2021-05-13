
`timescale 1 ns / 1 ps

//////////////////////////////////////////////////////////////////////////////////
// Engineer: Laurence Barker G8NJJ 
// 
// Create Date: 17.01.2019 21:00:43
// Design Name: 
// Module Name: Usr_Reg_Access
// Target Devices: Zynq 7000
// Tool Versions: Vivado 2018.1
// Description: Provide access to the USR_ACCESS primitive
//
// allows access to a register programmed into the bitstream settings
// useful for version numbers etc
// 
// Dependencies: none 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 


module Usr_Reg_Access
(
  output wire [31:0] Usr_Reg_Data,         // output data from config area
  output wire ConfigClock,
  output wire ConfigValid
);

USR_ACCESSE2 USR_ACCESS_Instance 
(
  .CFGCLK(ConfigClock),
  .DATA(Usr_Reg_Data),
  .DATAVALID(ConfigValid)
);

endmodule
