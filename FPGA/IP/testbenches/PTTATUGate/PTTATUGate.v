`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: HPSDR
// Engineer: Laurence Bsarker G8NJJ
// 
// Create Date: 28.11.2023 
// Design Name: 
// Module Name: PTTATUGate
// Project Name: Saturn 
// Target Devices: 
// Tool Versions: 
// Description: 
// simple code to assert PTT out if PTT is asserted except if there is an ATU tune demand.
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module PTTATUGate(
    input wire PTTIn,                    // active high PTT request in
    input wire ATURequest,               // active high ATU tune request
    input wire aclk,                     // clock
    output wire PTTOut,                  // active high PTT output
    input wire aresetn                   // active low reset
    );

reg ATUReq2 = 0, ATUReq3 = 0;               // regs to double register the ATU request
reg [1:0] State = 0;                        // state register
reg PTTOutReg = 0;                          // PTT out 

localparam Idle =0;
localparam PTTAsserted = 1;
localparam ATUActive = 2;

assign PTTOut = PTTOutReg;                  // RTT output from rgister variable

always @ (posedge aclk)
begin
    if(!aresetn)                            // if reset
    begin
        State <= 0;
        PTTOutReg <= 0;
    end
    else                                    // normal clock cycle
    begin
        ATUReq2 <= ATURequest;              // double register the ATU request in 
        ATUReq3 <= ATUReq2;
        case(State)
            Idle: begin
                PTTOutReg <= 0;
                if(PTTIn)
                begin
                    if(ATURequest)
                        State <= ATUActive;
                    else
                        State <= PTTAsserted;
                end
                end
        
            PTTAsserted: begin
                PTTOutReg <= 1;
                if(ATURequest)
                    State <= ATUActive;
                else if(!PTTIn)
                    State <= Idle;
            end
            
            ATUActive: begin
                PTTOutReg <= 0;
                if(!PTTIn)
                    State <= Idle;
            end
            
            default: begin
                State <= Idle;
            end
            
        endcase
    end
end

endmodule
