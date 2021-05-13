`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Laurence Barker G8NJJ 
// 
// Create Date: 24.06.2018 21:00:43
// Design Name: 
// Module Name: reg_to_axis
// Target Devices: Zynq 7000
// Tool Versions: Vivado 2018.1
// Description: registered axi stream create from parallel register
// 
// Dependencies: none 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module  reg_to_axis #
( parameter integer DIN_WIDTH  = 16)

(	input wire [DIN_WIDTH-1:0] data_in,
	input wire                 aclk,
	output wire [DIN_WIDTH-1:0] m_axis_tdata,
	output wire                m_axis_tvalid
);	 
    
	assign m_axis_tvalid = 1'b1;
    assign m_axis_tdata[DIN_WIDTH-1:0] = data_in[DIN_WIDTH-1:0];

endmodule


