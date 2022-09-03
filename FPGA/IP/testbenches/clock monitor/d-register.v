
`timescale 1 ns / 1 ps

//////////////////////////////////////////////////////////////////////////////////
// Engineer: Laurence Barker G8NJJ 
// 
// Create Date: 14.06.2022 22:00:43
// Design Name: 
// Module Name: D_register_norst
// Target Devices: Zynq 7000
// Tool Versions: Vivado 2018.1
// Description: D register with no reset
// 
// Dependencies: none 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 


module D_register_norst #
(
  parameter integer DATA_WIDTH = 16
)
(

(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK" *)
  input  wire                  aclk,        // register clock

  input  wire [DATA_WIDTH-1:0] din,         // input
  output reg  [DATA_WIDTH-1:0] dout         // output
);

  always @(posedge aclk)
  begin
      dout[DATA_WIDTH-1:0] <= din[DATA_WIDTH-1:0];
  end

endmodule
