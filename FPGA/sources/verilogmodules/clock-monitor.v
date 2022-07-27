
`timescale 1 ns / 1 ps

//////////////////////////////////////////////////////////////////////////////////
// Engineer: Laurence Barker G8NJJ 
// 
// Create Date: 14.06.2022 22:00:43
// Design Name: 
// Module Name: clock_monitor
// Target Devices: Artix 7
// Tool Versions: Vivado 2021.2
// Description: 4 input clock monitor
// 
// Dependencies: none 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// This code monitors 4 clocks. When it detects a rising edge,
// it loads a monostable count. This is re-loaded on a pos edge.
// doesn't detect falling edges - the logic being a rising
// edge needs there to have been a falling edge before it.
// if the count expires, that indicates absence of the clock.
// if all 4 clocks are present, an LED blinks.
// status of the 4 clocks provided for processor readback:
// bit=1 if clock considered present.
// all input clocks are asynchronous so are double registered.
// Design intent:
// clock this core from 125MHz XDMA clock_monitor
// input clocks:
// CK0 = 122.88MHz master clock
// CK1 = 10MHz
// CK2 = 122.88MHz config clock
// CK3 = 122.88MHz master clock (duplicate)


module clock_monitor #
(
  parameter integer MONOSTABLE_TICKS = 1000,
  parameter integer BLINK_HALFPERIOD = 62500000
)
(

(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK" *)
  input wire aclk,                      // register clock
  input wire aresetn,                   // reset
  input wire ck0,                       // clock input
  input wire ck1,                       // clock input
  input wire ck2,                       // clock input
  input wire ck3,                       // clock input
  output reg [3:0] dout,                // clock monitor data output
  output reg LED
);

localparam MONOWIDTH = clogb2(MONOSTABLE_TICKS);  // number of bits to hold monostable count
localparam BLINKWIDTH = clogb2(BLINK_HALFPERIOD);  // number of bits to hold blink period

  reg ck0_rega;                         // 1st register on clock 0
  reg ck0_regb;                         // 2nd register on clock 0
  reg ck1_rega;                         // 1st register on clock 1
  reg ck1_regb;                         // 2nd register on clock 1
  reg ck2_rega;                         // 1st register on clock 2
  reg ck2_regb;                         // 2nd register on clock 2
  reg ck3_rega;                         // 1st register on clock 3
  reg ck3_regb;                         // 2nd register on clock 3
  reg [MONOWIDTH-1:0] ck0count;         // clock 0 monostable counter
  reg [MONOWIDTH-1:0] ck1count;         // clock 1 monostable counter
  reg [MONOWIDTH-1:0] ck2count;         // clock 2 monostable counter
  reg [MONOWIDTH-1:0] ck3count;         // clock 3 monostable counter
  reg [BLINKWIDTH-1:0] blinkcount;      // clock 0 monostable counter
  reg LEDPLannedLit;                    // true if LED should be on if OK

//
// the clock monitoring is done separately for each clock
// clock monitoring. Strategy: continually sense a rising edge
// and load count; else decrement count.
//
  always @(posedge aclk)
  begin
      if(!aresetn)              // reset condition
      begin
        ck0_rega <= 0;
        ck0_regb <= 0;
        ck0count <= 0;
        ck1_rega <= 0;
        ck1_regb <= 0;
        ck1count <= 0;
        ck2_rega <= 0;
        ck2_regb <= 0;
        ck2count <= 0;
        ck3_rega <= 0;
        ck3_regb <= 0;
        ck3count <= 0;
      end
      else
      begin
        // ck0
        ck0_regb <= ck0_rega;       // 2nd register
        ck0_rega <= ck0;            // copy in raw async input
        
        if((ck0_regb==0) && (ck0_rega==1))      // rising edge aclk
        begin
            ck0count <= MONOSTABLE_TICKS;
            dout[0] <= 1;
        end
        else
        begin
            if(ck0count != 0)
                ck0count = ck0count - 1;
            else if(ck0count == 0)
                dout[0] <= 0;
        end
    
        // ck1
        ck1_regb <= ck1_rega;        // 2nd register
        ck1_rega <= ck1;            // copy in raw async input
        
        if((ck1_regb==0) && (ck1_rega==1))      // rising edge aclk
        begin
            ck1count <= MONOSTABLE_TICKS;
            dout[1] <= 1;
        end
        else
        begin
            if(ck1count != 0)
                ck1count = ck1count - 1;
            else if(ck1count == 0)
                dout[1] <= 0;
        end
    
        // ck2
        ck2_regb <= ck2_rega;       // 2nd register
        ck2_rega <= ck2;            // copy in raw async input
        
        if((ck2_regb==0) && (ck2_rega==1))      // rising edge aclk
        begin
            ck2count <= MONOSTABLE_TICKS;
            dout[2] <= 1;
        end
        else
        begin
            if(ck2count != 0)
                ck2count = ck2count - 1;
            else if(ck2count == 0)
                dout[2] <= 0;
        end
    
        // ck3
        ck3_regb <= ck3_rega;       // 2nd register
        ck3_rega <= ck3;            // copy in raw async input
        
        if((ck3_regb==0) && (ck3_rega==1))      // rising edge aclk
        begin
            ck3count <= MONOSTABLE_TICKS;
            dout[3] <= 1;
        end
        else
        begin
            if(ck3count != 0)
                ck3count = ck3count - 1;
            else if(ck3count == 0)
                dout[3] <= 0;
        end
      end
  end


//
// LED blink code.
// increment counter and set a bit saying LED should be on or off
// then every cycle set it to on if all dout bits set
// else set it to off.
//
  always @(posedge aclk)
  begin
    if(!aresetn)                        // reset everything
    begin
        LEDPLannedLit <= 0;
        LED <= 0;
        blinkcount <= 0;
    end
    else
    begin
        if(blinkcount != 0)
            blinkcount <= blinkcount - 1;
        else
        begin
            blinkcount <= (BLINK_HALFPERIOD - 1);
            LEDPLannedLit = ! LEDPLannedLit;
        end
        // finally if all clock bits set, LED = blinking else off
        if(dout[3:0] == 4'b1111)
            LED <= LEDPLannedLit;
        else
            LED <= 0;
    end
  end


function integer clogb2;
input [31:0] depth;
begin
  for(clogb2=0; depth>0; clogb2=clogb2+1)
  depth = depth >> 1;
end
endfunction



endmodule
