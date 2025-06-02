
`timescale 1 ns / 1 ps

//////////////////////////////////////////////////////////////////////////////////
// Engineer: Laurence Barker G8NJJ 
// 
// Create Date: 24.06.2018 21:00:43
// Design Name: 
// Module Name: D_register
// Target Devices: Zynq 7000
// Tool Versions: Vivado 2018.1
// Description: D register 
// 
// Dependencies: none 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 


module D_register #
(
  parameter integer DATA_WIDTH = 16
)
(

(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK" *)
(* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET resetn" *)
  input  wire                  aclk,        // register clock

(* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 resetn RST" *)
(* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input  wire                  resetn,      // active low reset
  input  wire [DATA_WIDTH-1:0] din,         // input
  output reg  [DATA_WIDTH-1:0] dout         // output
);

  always @(posedge aclk)
  begin
    if (!resetn)
      dout[DATA_WIDTH-1:0] <= {DATA_WIDTH{1'b0}};
    else
      dout[DATA_WIDTH-1:0] <= din[DATA_WIDTH-1:0];
  end

endmodule
