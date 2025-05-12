
`timescale 1 ns / 1 ps

//////////////////////////////////////////////////////////////////////////////////
// Engineer: Laurence Barker G8NJJ 
// 
// Create Date: 19.11.2018 21:00:43
// Design Name: 
// Module Name: to_offset_binary
// Target Devices: Zynq 7000
// Tool Versions: Vivado 2018.1
// Description: convert 2s complement to offset binary for MAX5891 DAC
// simply invert top bit.
//
// Dependencies: none 
// 
// Revision:
// Revision 0.01 - File Cre
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module cvt_offset_binary #(parameter DATA_WIDTH = 16)
(
  input  wire                  clk,         // register clock
  input  wire [DATA_WIDTH-1:0] din,         // input
  output reg  [DATA_WIDTH-1:0] dout         // output
);


  always @(posedge clk)
  begin
    dout[DATA_WIDTH-1:0] <= {~din[DATA_WIDTH-1], din[DATA_WIDTH-2:0]};
  end

endmodule
