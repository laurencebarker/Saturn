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
// waveshape from paper  "CW Shaping in DSP Software" by Alex Shovkoplyas, VE3NEA, QEX May/June 2006
// largely based on profile.v from Phil Haman VK6APH
// and modified for xilinx axi stream inspired by Pavel Demin's code
// for protocol 1: sample rate = 48KHz protocol 2: 192KHz
// (tvalid always asserted; the rate is throttled/set by the output tready signal)
// uses same ramp for both, but just takes every 4th sample @48KHz
// millisecond counting is based on a 122.88MHz clock.
//
// edited Laurence Barker 25/7/2021 to make the ramp time programmable. 
// interface amended to use a block RAM in block RAM controller mode, so the address bus 
// is sized by byte addresses. The memory now can't be initialised
// and will need to be written after power up over an axi4-lite bus.
// amended for protocol 2 data interface: 24 bit I/Q words therefore 24 bit ramp.
// added amplitude output to codec for sidetone amplitude.
// amplitude is output as a stream at 48KHz rate; a new sample generated
// every time m0_axis_tready asserted.
//
// interface signals:
//     delay_time:        delay in ms before ramp start after key down,
//                        and delay before ramp down begins
//     hang_time          delay in ms before PTT cw_key_ramp
//     ramp_length        ramp length in bytes (4*no. words)
//     keyer_enable       if 1, the keyer responds to key down and will key PTT
//     protocol_2         if 1, operates at 192KHz. It will step through the ramp
//                        one location (address step 4) at a time
//                        if 0, it steps through the ramp 4 words (16 bytes) per step
//                        This enables one stored ramp for both sample rates
//
//     m0_axis_xxxxx      AXI4 stream I/Q ramp signal. Q=0; I = amplitude.
//     m1_axis_xxxxx      AXI4 stream of amplitude samples ot the audio codec
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module cw_key_ramp
(
(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK" *)
(* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET aresetn" *)
    input wire aclk,                    // 12.288MHz clock (CODEC MCLK)
(* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
(* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input wire aresetn,                   // asynch reset
    input wire key_down,                // true when key down; must be already debounced
    input wire [7:0] delay_time,        // delay in ms before starting ram (while TX turns on) (0=no delay)
    input wire [9:0] hang_time,         // period in ms before PTT dropped (0=no hang)
    input wire [12:0] ramp_length,      // ramp length in words (changed from bytes)
    input wire keyer_enable,            // =1 to enable keyer
    input wire protocol_2,              // = 1 for protocol 2
    output reg CW_PTT,                  // PTT output; true
    output wire [47:0] m0_axis_tdata,   // ramp output axi stream 
    output wire m0_axis_tvalid,         // valid signal for stream
    input wire m0_axis_tready,          // tready: throttles ramp sample rate to 48KHz or 192KHz
    output reg [15:0] m1_axis_tdata,    // codec ampl output output axi stream 
    output reg m1_axis_tvalid,          // valid signal for codec ampl stream
    output wire bram_rst,               // block RAM active high reset
    output reg [31:0] bram_addr,        // address output to synchronous block RAM (byte address)
    output reg        bram_enable,      // 1 = memory in use 
    output reg [3:0] bram_web,          // byte write enables     
    input wire [31:0] bram_data         // data in from synchronous block RAM
    );


reg [3:0] ramp_state = 0;               // sequencer state
reg [16:0] millis_count = 0;            // millisecond counter (14 bit/16384 max)
reg [9:0] delay_count = 0;              // delay or hang counter
reg [15:0] ramp_length_reg = 0;         // ramp length value
reg [47:0] m0_axis_tdata_reg;           // I/Q data value
reg [1:0] decimate_count = 0;           // reads to decimate; output codec ampl if zero
reg [4:0] address_increment = 0;        // protocol dependent address increment (4 or 16)

localparam MILLISEC_COUNT = 122880;     // clock counts for 1ms @ 122.88MHz clock

always @ (posedge aclk)
begin
    if (!aresetn)
    begin
        ramp_state <= 0;                // reset sequencer
        millis_count <= 0;              // clear counters
        delay_count <= 0;
        ramp_length_reg <= 0;           // clear ramp length
        bram_addr <= 0;                 // reset RAM address
        bram_enable <= 0;               // not enabled initially
        bram_web <= 3'b0;               // never write
        CW_PTT <= 0;                    // clear keyer PTT output
        m0_axis_tdata_reg <= 0;         // no output data
        address_increment <= 0;         // steps to change address by
        decimate_count <= 0;            // codec o/p decimate
        m1_axis_tvalid <= 0;            // no amplitude output
        m1_axis_tdata <= 0;
    end
    else                                // not reset - normal operation
    begin
    //
    // drive out a new sample for m1_axis amplitude stream if m0_axis_tready
    // is asserted. 
    // If protocol2, decimate by 4 to 48KHz.
    // If P1, sample rate should already be 48KHz so send every beat.
    //
        if(m1_axis_tvalid)              // deassert after 1 cycle
            m1_axis_tvalid <= 0;
        if(m0_axis_tready)
        begin
            if(protocol_2 == 1)                     // if protocol 2, increment decimate reg
                decimate_count <= decimate_count+1; // scroll round 0-1-2-3-0-1 etc
            else
                decimate_count <= 0;                // always 
            if(!decimate_count)         // if a new stream 0 beat
            begin
                m1_axis_tdata[15:0] <= m0_axis_tdata_reg[23:8];     // top 16 bits 
                m1_axis_tvalid <= 1;
            end
        end
//
// now do state dependent actions
//        
        case(ramp_state)                                // sequencer
       
        0: begin                                        // idle state - wait for key
            bram_addr <= 0;
            bram_enable <= 0;
            m0_axis_tdata_reg <= 0;                     // no output data
            m1_axis_tdata <= 0;
            if(key_down && keyer_enable)
            begin
                ramp_length_reg <= (ramp_length << 2);
                if(protocol_2 == 1)
                    address_increment <= 4;             // 1 word steps for protocol 2
                else 
                    address_increment <= 16;            // 4 word steps for protocol 1
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

        
        1:  begin                                           // count delay before ramp
            m0_axis_tdata_reg <= 0;
            bram_enable <= 1;                               // enable block memory while active
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


//
// in this state we ramp up, but throttled by tready        
// now check if address needs incrementing if tready asserted
//
        2:  begin                                       // ramping amplitude up & dwell while key down
            m0_axis_tdata_reg[23:0] <= bram_data[23:0];
            if (m0_axis_tready)
            begin
                if(bram_addr < ramp_length_reg)
                    bram_addr <= (bram_addr + address_increment);
 // some clocks later, get data from register
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

//
// key is down, and remp complete
//        
        3: begin                                        // counting delay before ramp down
            m0_axis_tdata_reg[23:0] <= bram_data[23:0];
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

//
// key released, and delay complete - ramp back down
// now check if address needs decrementing if tready asserted
//        
        4:  begin                        // ramping down
            m0_axis_tdata_reg[23:0] <= bram_data[23:0];
            if (m0_axis_tready)
            begin
                if(bram_addr != 0)
                    bram_addr <= (bram_addr - address_increment);
// some clocks later, get data from BRAM input
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
            m0_axis_tdata_reg <= 0;
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

assign bram_rst = ~aresetn;               // active high reset
assign m0_axis_tvalid = 1'b1;            // output data always available                 
assign m0_axis_tdata[47:0] = m0_axis_tdata_reg[47:0];   // output data from register




function integer clogb2;
input [31:0] depth;
begin
  for(clogb2=0; depth>0; clogb2=clogb2+1)
  depth = depth >> 1;
end
endfunction

endmodule
