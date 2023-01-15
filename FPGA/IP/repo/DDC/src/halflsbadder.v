`timescale 1 ns / 1 ps

//////////////////////////////////////////////////////////////////////////////////
// Engineer: Laurence Barker G8NJJ 
// 
// Create Date: 05.01.2023 // Design Name: 
// Module Name: HalfLSBAdder
// Target Devices: Artix 7
// Tool Versions: Vivado 2021.1
// Description: adds a half LSB to input word, and makes word 1 bit wider 
// 
// Dependencies: none 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module HalfLSBAdder #
(
  parameter integer DATA_WIDTH = 16
)
(
  // System signals
  input  wire                        aclk,
  input  wire [DATA_WIDTH-1:0] input_data,
  output reg [DATA_WIDTH:0] output_data
);

  always @(posedge aclk)
  begin
    output_data <= (input_data << 1) + 1;
  end

endmodule