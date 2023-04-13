
`timescale 1 ns / 1 ps

//////////////////////////////////////////////////////////////////////////////////
// Engineer: Laurence Barker G8NJJ 
// 
// Create Date: 7/4/2023
// Design Name: Saturn
// Module Name: linear feedback random number generator
// Target Devices: Artix 7
// Tool Versions: Vivado 2021.1
// Description: LFSR to generate random bit; then made into axi stream
// this is for the complex multiplier random rounding
// 22 bit LFSR uses taps on bits 0&21
// 
// Dependencies: none 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module LFSR_Random_Number_Generator
(
//////////////////////////////////////////////////////////////////////////////////
// Declare the attributes above the port declaration

(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK" *)
    input wire          aclk,        // register clock
    input wire          aresetn,
    output wire [7:0]   m_axis_tdata,         // output
    output wire         m_axis_tvalid
);
    localparam InitialValue = 1;
    reg [22:0] LFSR = InitialValue;

    assign m_axis_tdata[7:0] = LFSR[7:0];
    assign m_axis_tvalid = 1;


    always @(posedge aclk)
    begin
        if(!aresetn)
            LFSR <= InitialValue;
        else
        begin
            LFSR[21] <= LFSR[21] ^ LFSR[0];
            LFSR[20:0] <= LFSR[21:1];
        end
    end

endmodule
