
`timescale 1 ns / 1 ps

//////////////////////////////////////////////////////////////////////////////////
// Engineer: Laurence Barker G8NJJ 
// 
// Create Date: 24.06.2018 21:00:43
// Design Name: 
// Module Name: regmux_2_1
// Target Devices: Zynq 7000
// Tool Versions: Vivado 2018.1
// Description: Test bench for 2:1 registered multiplexer 
// 
// Dependencies: none 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module regmux_2_1 #
(
  parameter integer DATA_WIDTH = 16
)
(
  input  wire                  sel,         // mux input select
(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK" *)
(* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET resetn" *)
  input  wire                  aclk,         // register clock
(* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 resetn RST" *)
(* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input  wire                  resetn,        // active low reset
  input  wire [DATA_WIDTH-1:0] din0,        // 1st input
  input  wire [DATA_WIDTH-1:0] din1,        // 2nd input
  output reg  [DATA_WIDTH-1:0] dout         // output
);

  always @(posedge aclk)
  begin
    if (!resetn)
      dout[DATA_WIDTH-1:0] <= {DATA_WIDTH{1'b0}};
    else
    begin
      case(sel)
        1'b0: dout[DATA_WIDTH-1:0] <= din0[DATA_WIDTH-1:0];
        1'b1: dout[DATA_WIDTH-1:0] <= din1[DATA_WIDTH-1:0];
      endcase
    end
  end

endmodule
