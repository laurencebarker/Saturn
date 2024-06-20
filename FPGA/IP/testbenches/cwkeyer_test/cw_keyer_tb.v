`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    23.07.2021 16:42:01
// Design Name:    CW keyer IP testbench
// Module Name:    Keyer_Testbench
// Project Name:   Saturn
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    Testbench for CW keyer
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 


module keyer_ip_tb( );

//////////////////////////////////////////////////////////////////////////////////
// Test Bench Signals
//////////////////////////////////////////////////////////////////////////////////
// Clock and Reset
reg aclk = 0;
reg aresetn = 1;

reg key_down = 0;
reg [7:0] delay_time;
reg [9:0] hang_time;
reg [12:0] ramp_length;
reg keyer_enable;
reg protocol_2;
wire CW_PTT;
wire [47:0] m0_axis_tdata;   // ramp output axi stream 
wire m0_axis_tvalid;         // valid signal for stream
wire m0_axis_tready;          // tready: throttles ramp sample rate to 48KHz or 192KHz
wire [15:0] m1_axis_tdata;    // codec ampl output output axi stream 
wire m1_axis_tvalid;          // valid signal for codec ampl stream
wire bram_rst;               // block RAM active high reset
wire [31:0] bram_addr;        // address output to synchronous block RAM (byte address)
wire        bram_enable;      // 1 = memory in use 
wire [3:0] bram_web;          // byte write enables     
reg [31:0] bram_data;         // data in from synchronous block RAM
//
// clockdivider signals
//
wire TCN;
wire ClockOut;



cw_key_ramp UUT
(
    .aclk            (aclk),
    .aresetn         (aresetn),
    .key_down        (key_down),
    .delay_time      (delay_time),
    .hang_time       (hang_time),
    .ramp_length     (ramp_length),
    .keyer_enable    (keyer_enable),
    .protocol_2      (protocol_2),
    .CW_PTT          (CW_PTT),
    .m0_axis_tdata   (m0_axis_tdata),
    .m0_axis_tvalid  (m0_axis_tvalid),
    .m0_axis_tready  (m0_axis_tready),
    .m1_axis_tdata   (m1_axis_tdata),
    .m1_axis_tvalid  (m1_axis_tvalid),
    .bram_rst        (bram_rst),
    .bram_addr       (bram_addr),
    .bram_enable     (bram_enable),
    .bram_web        (bram_web),
    .bram_data       (bram_data)
);


//
// instantiate a clock divider to generate TReady
// divide by 2560 to get 48KHz for protocol 1 modulation Fs
ClockDivider #(2560) Div 
(
    .aclk            (aclk),
    .resetn          (aresetn),
    .ClockOut        (ClockOut),
    .TC              (m0_axis_tready),
    .TCN             (TCN)
);

parameter CLK_PERIOD=8.1380208;              // 122.88MHz
// Generate the clock : 122.88 MHz    
always #(CLK_PERIOD/2) aclk = ~aclk;


//////////////////////////////////////////////////////////////////////////////////
// Main Process
//////////////////////////////////////////////////////////////////////////////////
//
initial begin
    //Assert the reset
    aresetn = 0;
    #340
    // Release the reset
    aresetn = 1;
end
initial begin    

hang_time = 10;
delay_time=3;
protocol_2=0;
keyer_enable=1;
ramp_length = 3840;         // 960*4

//key down after 1us;
// key up after 20ms
#1000
key_down=1;
#20000000
key_down=0;
end

//
// emulate a RAM, with memory content
// 
always @(posedge aclk)
begin
    bram_data = bram_addr * 2000;
end


endmodule
