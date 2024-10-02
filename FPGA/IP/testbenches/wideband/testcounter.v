//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR 
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    11.10.2022 
// Design Name:    testcounter.v
// Module Name:    Test_Counter
// Project Name:   Saturn 
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    Module to generate a counting data sequence on a 16 bit bus, for test
// generates a new count value on each clock cycle
// the top bit selected from the parameter

// 
// I/O signals:
//          aclk                master clock
//          aresetn             active low asynchronous reset signal
//          countout            output bus
//          clear               active high input; clears count
//
// Dependencies: 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: 
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1 ns / 1 ps


module Test_Counter #
(
  parameter IsADC1 = 000000          // top bit set if ADC1
)
(
  // System signals
  input wire                        aclk,
  input wire                        aresetn,
  input wire                        clear,
  // AXI bus
  output reg [15:0]                 countout        // output data
);



//
//
//
    always @(posedge aclk)
    begin
        if (~aresetn)                   // reset processing
        begin
            countout <= 0;
        end
        
        else                            // normal processing
        begin
            if (clear && !IsADC1)
                countout <= 16'h0;
            else if (clear && IsADC1)
                countout <= 16'h8000;
            else
                countout <= countout + 1;
        end
    end

endmodule