
`timescale 1 ns / 1 ps

//////////////////////////////////////////////////////////////////////////////////
// Engineer: Laurence Barker G8NJJ 
// 
// Create Date: 24.06.2018 21:00:43
// Design Name: 
// Module Name: regmux_8_1
// Target Devices: Zynq 7000
// Tool Versions: Vivado 2018.1
// Description: 8:1 registered multiplexer 
// 
// Dependencies: none 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module regmux_8_1 #
(
  parameter integer DATA_WIDTH = 16
)
(
  input  wire [2:0]            sel,
(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK" *)
(* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET resetn" *)
  input  wire                  aclk,
(* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 resetn RST" *)
(* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input  wire                  resetn,        // active low synch reset
  input  wire [DATA_WIDTH-1:0] din0,
  input  wire [DATA_WIDTH-1:0] din1,
  input  wire [DATA_WIDTH-1:0] din2,
  input  wire [DATA_WIDTH-1:0] din3,
  input  wire [DATA_WIDTH-1:0] din4,
  input  wire [DATA_WIDTH-1:0] din5,
  input  wire [DATA_WIDTH-1:0] din6,
  input  wire [DATA_WIDTH-1:0] din7,
  output reg  [DATA_WIDTH-1:0] dout
);

  always @(posedge aclk)
  begin
    if (!resetn)
      dout[DATA_WIDTH-1:0] <= {DATA_WIDTH{1'b0}};
    else
    begin
      case(sel[2:0])
        3'd0: dout[DATA_WIDTH-1:0] <= din0[DATA_WIDTH-1:0];
        3'd1: dout[DATA_WIDTH-1:0] <= din1[DATA_WIDTH-1:0];
        3'd2: dout[DATA_WIDTH-1:0] <= din2[DATA_WIDTH-1:0];
        3'd3: dout[DATA_WIDTH-1:0] <= din3[DATA_WIDTH-1:0];
        3'd4: dout[DATA_WIDTH-1:0] <= din4[DATA_WIDTH-1:0];
        3'd5: dout[DATA_WIDTH-1:0] <= din5[DATA_WIDTH-1:0];
        3'd6: dout[DATA_WIDTH-1:0] <= din6[DATA_WIDTH-1:0];
        3'd7: dout[DATA_WIDTH-1:0] <= din7[DATA_WIDTH-1:0];
      endcase
    end
  end

endmodule
