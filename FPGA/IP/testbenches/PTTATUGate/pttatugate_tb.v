`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    10/12/2023
// Design Name:    PTTATUGate testbench
// Module Name:    PTTATUGate_testbench
// Project Name:   Saturn
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    Testbench for PTT ATU Gate
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 


module ptt_atu_gate_tb( );

//////////////////////////////////////////////////////////////////////////////////
// Test Bench Signals
//////////////////////////////////////////////////////////////////////////////////
// Clock and Reset
reg aclk = 0;
reg aresetn = 1;
reg PTTIn = 0;                  // active high PTT request in
reg ATURequest = 0;             // active high ATU tune request
wire PTTOut;                  	// active high PTT output



PTTATUGate UUT
(
    .aclk     (aclk),
    .aresetn  (aresetn),
    .PTTIn     (PTTIn),
    .ATURequest (ATURequest),
    .PTTOut (PTTOut)
);

parameter CLK_PERIOD=8.0;              // 125MHz
// Generate the clock : 125 MHz    
always #(CLK_PERIOD/2) aclk = ~aclk;


//////////////////////////////////////////////////////////////////////////////////
// Main Process
//////////////////////////////////////////////////////////////////////////////////
//
initial begin
    //Assert the reset
    aresetn = 0;
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    // Release the reset
    aresetn = 1;
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);

// assert PTT In with no ATU request. PTT out should be driven
    #2
    ATURequest = 0;     // no ATU request
    PTTIn = 1;          // assert strobes
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);

// deassert PTT in
    #2
    PTTIn = 0;          // deassert strobes
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);

// assert ATU request. PTT out should NOT be asserted.
    #2
    ATURequest = 1;          // assert strobes
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);

// deassert ATU request
    #2
    ATURequest = 0;          // deassert strobes
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);

// assert PTT In with ATU request. PTT out should NOT be driven
    #2
    ATURequest = 1;     // assert strobes
    PTTIn = 1;          // assert strobes
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);

// deassert PTT in
    #2
    PTTIn = 0;          // deassert strobes
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);


// assert PTT In after a few cycles assert ATU request. PTT out should be driven, then drop
    #2
    ATURequest = 0;     // deassert strobes
    PTTIn = 1;          // assert strobes
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);

    #2
    ATURequest = 1;          // assert strobes
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);

// deassert PTT in
    #2
    PTTIn = 0;          // assert strobes
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);
    @ (posedge aclk);


end

endmodule