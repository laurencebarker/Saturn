`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: HPSDR
// Engineer: Laurence Bsarker G8NJJ
// 
// Create Date: 24.11.2018 10:24:28
// Design Name: 
// Module Name: cw_key_ramp
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// Generates 5ms ramp for CW rising and gfalling edge.
// waveshape from paper ""
// largely based on profile.v from Phil Haman VK6APH
// and modified for xilinx axi stream inspired by Pavel Demin's code
// for protocol 1: sample rate = 48KHz protocol 2: 192KHz
// uses same ramp for both, but just takes every 4th sample @48KHz
//
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module cw_key_ramp #(parameter RAMP_END = 239, parameter is_audio=1)
(
(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK" *)
(* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET resetn" *)
    input wire aclk,                    // 12.288MHz clock (CODEC MCLK)
(* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 resetn RST" *)
(* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input wire resetn,                   // asynch reset
    input wire key_down,                // true when key down; must be already debounced
    input wire [7:0] delay_time,        // delay in ms before starting ram (while TX turns on) (0=no delay)
    input wire [9:0] hang_time,         // period in ms before PTT dropped (0=no hang)
    input wire keyer_enable,            // =1 to enable keyer
    input wire protocol_2,              // = 1 for protocol 2
    output reg CW_PTT,                  // PTT output; true
    output wire [31:0] m_axis_tdata,    // ramp output axi stream 
    output wire m_axis_tvalid,          // valid signal for stream
    input wire m_axis_tready,           // tready: throttles ramp sample rate to 48KHz
    output wire bram_rst,               // block RAM active high reset
    output reg [9:0] bram_addr,         // address output to synchronous block RAM
    input wire [15:0] bram_data         // data in from synchronous block RAM
    );


reg [3:0] ramp_state = 0;               // sequencer state
reg [13:0] millis_count = 0;            // millisecond counter (14 bit/16384 max)
reg [9:0] delay_count = 0;              // delay or hang counter

localparam MILLISEC_COUNT = 12287;      // clock counts for 1ms, -1


always @ (posedge aclk)
begin
    if (!resetn)
    begin
        ramp_state <= 0;                // reset sequencer
        millis_count <= 0;              // clear counters
        delay_count <= 0;
        bram_addr <= 0;                 // reset RAM address
        CW_PTT=0;                       // clear keyer PTT output
    end
    else                                // not reset - normal operation
    begin
        case(ramp_state)                                // sequencer
        
        0: begin                                        // idle state - wait for key
            bram_addr <= 0;
            if(key_down && keyer_enable)
            begin
                CW_PTT <= 1;                            // assert PTT
                if(delay_time != 0)
                begin
                    delay_count <= delay_time-1;          // load timers
                    millis_count <= MILLISEC_COUNT;
                    ramp_state <= 1;                    // count delay
                end
                else
                    ramp_state <= 2;                    // straight to ramp
            end
            else                                        // staying in idle
            begin
                CW_PTT <= 0;                            // no PTT o/p
                delay_count <= 0;                       // clear timers
                millis_count <= 0;
            end 
        end

        
        1:  begin                                        // count delay before ramp
            if (millis_count == 0)                          // if millisecond count expired, update delay counter
            begin
                if (delay_count == 0)                       // if expired, move to next state
                    ramp_state <= 2;
                else
                begin
                    millis_count = MILLISEC_COUNT;
                    delay_count = delay_count - 1;          // decrement counter if not all done
                end
            end
            else
                millis_count = millis_count - 1;            // decrement milisecond counter
        end


// in this state we ramp up, but throttled by tready        
        2:  begin                                        // ramping amplitude up & dwell while key down
            if (m_axis_tready)
            begin
                if(bram_addr < RAMP_END)
                    if(protocol_2)                      // increment if not complete - by 1 or 4
                        bram_addr = bram_addr + 1;          // increment if not at end
                    else
                        bram_addr = bram_addr + 4;
                else
                begin
                    if (!(key_down && keyer_enable))    // if key no longer active
                    begin
                        if (delay_time == 0)            // if no delay begin ramp down
                            ramp_state <= 4;
                        else
                        begin
                            ramp_state <= 3;            // else delay
                            delay_count <= delay_time-1;  // load timers
                            millis_count <= MILLISEC_COUNT;
                        end
                    end
                end
            end
        end

        
        3: begin                                        // counting delay before ramp down
            if (millis_count == 0)                          // if millisecond count expired, update delay counter
            begin
                if (delay_count == 0)                       // if expired, move to next state
                    ramp_state <= 4;
                else
                begin
                    delay_count = delay_count - 1;          // decrement counter if not all done
                    millis_count = MILLISEC_COUNT;
                end
            end
            else
                millis_count = millis_count - 1;            // decrement milisecond counter
        end

        
        4:  begin                        // ramping down
            if (m_axis_tready)
            begin
                if(bram_addr != 0)
                    if(protocol_2)                          // decrement if not at end
                        bram_addr = bram_addr - 1;
                    else
                        bram_addr = bram_addr - 4;
                else
                begin
                    if (hang_time == 0)                 // if no hang after ramp
                        ramp_state <= 0;
                    else
                    begin
                        ramp_state <= 5;                // else delay
                        delay_count <= hang_time-1;       // load timers
                        millis_count <= MILLISEC_COUNT;
                    end
                end
            end         // if tready
        end


//
// in this state: if key pressed again, go to states 1 or 2 (depending on whether delay is needed)
// else count down, go to idle when expired        
//
        5:  begin                        // hang count with PTT still active
            if(key_down && keyer_enable)
            begin
                if(delay_time != 0)
                begin
                    delay_count <= delay_time-1;          // load timers
                    millis_count <= MILLISEC_COUNT;
                    ramp_state <= 1;                    // count delay
                end
                else
                    ramp_state <= 2;                    // straight to ramp
            end
            else                                        // no new key; decrement counts
            begin
                if (millis_count == 0)                          // if millisecond count expired, update delay counter
                begin
                    if (delay_count == 0)                       // if expired, move to back to idle
                        ramp_state <= 0;
                    else
                    begin
                        delay_count = delay_count - 1;          // decrement counter if not all done
                        millis_count = MILLISEC_COUNT;
                    end
                end
                else
                    millis_count = millis_count - 1;            // decrement milisecond counter
            end

        end

        default: begin
            ramp_state <= 0;
        end
        endcase    
    end
end

assign bram_rst = ~resetn;               // active high reset
assign m_axis_tvalid = 1'b1;            // output data always available                 
assign m_axis_tdata[15:0] = bram_data[15:0];        // o/p data straight from ROM
if(is_audio)
    assign m_axis_tdata[31:16] = bram_data[15:0];   // same to left and right
else
    assign m_axis_tdata[31:16] = 16'b0;   // zero Q value


function integer clogb2;
input [31:0] depth;
begin
  for(clogb2=0; depth>0; clogb2=clogb2+1)
  depth = depth >> 1;
end
endfunction

endmodule
