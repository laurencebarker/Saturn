
`timescale 1 ns / 1 ps

//////////////////////////////////////////////////////////////////////////////////
// Engineer: Laurence Barker G8NJJ 
// 
// Create Date: 19.11.2018 21:00:43
// Design Name: 
// Module Name: LTC2208_derandomise 
// Target Devices: Zynq 7000
// Tool Versions: Vivado 2018.1
// Description: de-randomise LTC2208 output data 
//  A Digital Output Randomizer is fitted to the LTC2208. 
// This complements bits 15 to 1 if bit 0 is 1. This helps to reduce any pickup
// by the A/D input of the digital outputs. 
// We need to de-ramdomize the LTC2208 data if this is turned on. 
//
// Dependencies: none 
// 
// code originally written by Phil Harman VK6APH
// Revision:
// Revision 0.01 - File Cre
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module LTC2208_derandomise #(parameter DATA_WIDTH = 16)
(
  input  wire                  clk,         // register clock
  input  wire                  rand_sel,    // 1=random ON
  input  wire [DATA_WIDTH-1:0] din,         // input
  output reg  [DATA_WIDTH-1:0] dout         // output
);

 reg  [DATA_WIDTH-1:0] InputData;           // input latch
  
  always @(posedge clk)
  begin
    InputData [DATA_WIDTH-1:0] <= din [DATA_WIDTH-1:0];         // copy new input data
    
    if (rand_sel)
    begin
    	if (InputData[0])
            dout[DATA_WIDTH-1:0] <= {~InputData[15:1],InputData[0]};
        else
            dout[DATA_WIDTH-1:0] <= InputData[DATA_WIDTH-1:0];

    end
    else    
      dout[DATA_WIDTH-1:0] <= InputData[DATA_WIDTH-1:0];
  end

endmodule
