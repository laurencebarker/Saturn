`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    23.07.2021 16:42:01
// Design Name:    CW keyer testbench
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


//Step 2 - Import two required packages: axi_vip_pkg and <component_name>_pkg.
import axi_vip_pkg::*;
import keyer_block_axi_vip_0_0_pkg::*;




module keyer_tb( );

//////////////////////////////////////////////////////////////////////////////////
// Test Bench Signals
//////////////////////////////////////////////////////////////////////////////////
// Clock and Reset
reg aclk = 0;
reg aresetn = 1;

reg [7:0] delay_time;
reg [9:0] hang_time;
reg [12:0] ramp_length;
reg key_down;
reg keyer_enable;
reg protocol_2;

wire CW_PTT;
wire [47:0] m_axis_tdata;
wire m_axis_tvalid;

wire [15:0] m1_axis_tdata_amplitude;
wire m1_axis_tvalid_amplitude;

reg base_addr = 32'hC0000000;
reg [31:0] addr;
reg [31:0] data;
xil_axi_resp_t 	resp;



keyer_block_wrapper UUT
(
    .aclk            (aclk),
    .aresetn         (aresetn),
    .delay_time      (delay_time),
    .hang_time       (hang_time),
    .key_down        (key_down),
    .keyer_enable    (keyer_enable),
    .m_axis_tdata    (m_axis_tdata),
    .ramp_length     (ramp_length),
    .m_axis_tvalid   (m_axis_tvalid),
    .m1_axis_tdata_amplitude    (m1_axis_tdata_amplitude),
    .m1_axis_tvalid_amplitude   (m1_axis_tvalid_amplitude),
    .protocol_2      (protocol_2),
    .CW_PTT          (CW_PTT)

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

//////////////////////////////////////////////////////////////////////////////////
// The following part controls the AXI VIP. 
//It follows the "Useful Coding Guidelines and Examples" section from PG267
//////////////////////////////////////////////////////////////////////////////////
//
// Step 3 - Declare the agent for the master VIP
keyer_block_axi_vip_0_0_mst_t      master_agent;



initial begin    

ramp_length=4092;
hang_time = 10;
delay_time=3;
protocol_2=0;
keyer_enable=1;
//key down after 1us;
// key up after 20ms

// Step 4 - Create a new agent
master_agent = new("master vip agent",UUT.keyer_block_i.axi_vip_0.inst.IF);

// Step 5 - Start the agent
master_agent.start_master();
    
    //Wait for the reset to be released
  wait (aresetn == 1'b1);

//
// the block RAM can't be initialised in block RAM controller mode
// so write it with a simple RAM. This will show up in the simulation plot
//
for(addr=0; addr < 4096; addr=addr+4)
begin
    data=addr * 2048;
    master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);
end
for(addr=4096; addr < 8192; addr=addr+4)
begin
    master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,8388607,resp);
end




//
// now begin the testbench proper
//
#1000
key_down=1;
#20000000           // wait to release key
key_down=0;

end
endmodule
