
`timescale 1 ns / 1 ps

//////////////////////////////////////////////////////////////////////////////////
// Engineer: Laurence Barker G8NJJ 
// 
// Create Date: 24.06.2018 21:00:43
// Design Name: 
// Module Name: double D_register for asynchronous inputs
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
//////////////////////////////////////////////////////////////////////////////////

module Double_D_register #
(
  parameter integer DATA_WIDTH = 16
)
(
//////////////////////////////////////////////////////////////////////////////////
// Declare the attributes above the port declaration

(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK" *)
  input  wire                  aclk,        // register clock

  input  wire [DATA_WIDTH-1:0] din,         // input
  output wire  [DATA_WIDTH-1:0] dout         // output

);

  (* ASYNC_REG = "TRUE" *) reg [DATA_WIDTH-1:0] Intermediate;
  (* ASYNC_REG = "TRUE" *) reg [DATA_WIDTH-1:0] Intermediate2;

    assign dout[DATA_WIDTH-1:0] = Intermediate2[DATA_WIDTH-1:0];


  always @(posedge aclk)
  begin
      Intermediate[DATA_WIDTH-1:0] <= din[DATA_WIDTH-1:0];
      Intermediate2[DATA_WIDTH-1:0] <= Intermediate[DATA_WIDTH-1:0];
  end

endmodule
