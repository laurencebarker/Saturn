`timescale 1ns / 1ps
//-----------------------------------------------------------------
// (c) Copyright 1984 - 2018 Xilinx, Inc. All rights reserved.	
//							
// This file contains confidential and proprietary information
// of Xilinx, Inc. and is protected under U.S. and
// international copyright and other intellectual property
// laws.							
//-----------------------------------------------------------------							 
// DISCLAIMER							
// This disclaimer is not a license and does not grant any	 
// rights to the materials distributed herewith. Except as	 
// otherwise provided in a valid license issued to you by	
// Xilinx, and to the maximum extent permitted by applicable
// law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
// WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
// AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
// BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-	 
// INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and	 
// (2) Xilinx shall not be liable (whether in contract or tort,	
// including negligence, or under any other theory of
// liability) for any loss or damage of any kind or nature 
// related to, arising under or in connection with these	 
// materials, including for any direct, or any indirect,	
// special, incidental, or consequential loss or damage		 
// (including loss of data, profits, goodwill, or any type of	
// loss or damage suffered as a result of any action brought	
// by a third party) even if such damage or loss was		 
// reasonably foreseeable or Xilinx had been advised of the	 
// possibility of the same.					 
//								 
// CRITICAL APPLICATIONS					 
// Xilinx products are not designed or intended to be fail-	 
// safe, or for use in any application requiring fail-safe	 
// performance, such as life-support or safety devices or	 
// systems, Class III medical devices, nuclear facilities,	 
// applications related to the deployment of airbags, or any	 
// other applications that could lead to death, personal	 
// injury, or severe property or environmental damage		 
// (individually and collectively, "Critical			 
// Applications"). Customer assumes the sole risk and		 
// liability of any use of Xilinx products in Critical		 
// Applications, subject only to applicable laws and		 
// regulations governing limitations on product liability.	 
//								 
// THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS	 
// PART OF THIS FILE AT ALL TIMES. 				 
//-----------------------------------------------------------------
// ************************************************************************
//
//-----------------------------------------------------------------------------
// Filename:        AXI_GPIO_tb.sv
// Version:         v1.0
// Description:     Simulation test bench for the AXI Basics Series 3
//                  
//-----------------------------------------------------------------------------
//Step 2 - Import two required packages: axi_vip_pkg and <component_name>_pkg.
import axi_vip_pkg::*;
import AXI_GPIO_Sim_axi_vip_0_0_pkg::*;



//////////////////////////////////////////////////////////////////////////////////
// Test Bench Signals
//////////////////////////////////////////////////////////////////////////////////
// Clock and Reset
bit aclk = 0, aresetn = 1;
//Simulation output
bit MISO, MOSI, SCLK, nCS;
bit int1_out;
bit fifo1_overflow;
bit[15:0] fifo1_count;
bit int2_out;
bit fifo2_overflow;
bit[15:0] fifo2_count;
bit int3_out;
bit fifo3_overflow;
bit[15:0] fifo3_count;
bit int4_out;
bit fifo4_overflow;
bit[15:0] fifo4_count;
bit overrange1;
bit overrange2;
bit [15:0] ADC1data;
bit [15:0] ADC2data;
bit TX_Strobe;
bit SPI_data;
bit SPI_ck;
bit Rx_load_strobe;
bit Tx_load_strobe;
bit test_fifo_tvalid;
bit [7:0] test_fifo_tdata;
bit fifo_tready;


//AXI4-Lite signals
xil_axi_resp_t 	resp;
bit[31:0]  addr, data, base_addr = 32'h44A0_0000, switch_state;

module AXI_FIFO_Overflow_tb( );

AXI_GPIO_Sim_wrapper UUT
(
    .aclk               (aclk),
    .aresetn            (aresetn),
    .overrange1           (overrange1),
    .overrange2           (overrange2),
    .ADC1data             (ADC1data),
    .ADC2data             (ADC2data)

);

// Generate the clock : 125 MHz    
always #4ns aclk = ~aclk;

//////////////////////////////////////////////////////////////////////////////////
// Main Process
//////////////////////////////////////////////////////////////////////////////////
//
initial begin
    //Assert the reset
    aresetn = 0;
    overrange1=0;
    overrange2=0;
    ADC1data = 0;
    ADC2data=0;
    #10us
    // Release the reset
    aresetn = 1;
end
//
//////////////////////////////////////////////////////////////////////////////////
// The following part controls the AXI VIP. 
//It follows the "Useful Coding Guidelines and Examples" section from PG267
//////////////////////////////////////////////////////////////////////////////////
//
// Step 3 - Declare the agent for the master VIP
AXI_GPIO_Sim_axi_vip_0_0_mst_t      master_agent;

//
initial begin    

// Step 4 - Create a new agent
master_agent = new("master vip agent",UUT.AXI_GPIO_Sim_i.axi_vip_0.inst.IF);

// Step 5 - Start the agent
master_agent.start_master();
    
	#10us
    
    //Wait for the reset to be released
    wait (aresetn == 1'b1);
	#10us
	

////////////////////////////////////////////////////////////////////////////////
//
// ADC overrange latch
$display("Testing ADC Overrange latch:");
    
#100ns
// read overflow then ADC registers:
addr = 32'h00000000;
data = 32'b0;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("initial read ADC overrange latch: data = 0x%x", data);    

#100ns
addr = 32'h00000004;
data = 32'b0;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("initial read ADC1 peak latch: data = %d", data);    

#100ns
addr = 32'h00000008;
data = 32'b0;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("initial read ADC2 peak latch: data = %d", data);    

#2
overrange1 = 1'b1;
ADC1data = 7;
@(posedge aclk);
#2
overrange1 = 1'b0;
ADC1data=3;
@(posedge aclk);
#2
ADC1data=0;
@(posedge aclk);
@(posedge aclk);

#100ns
// read overflow then ADC registers:
addr = 32'h00000000;
data = 32'b0;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("2nd read ADC overrange latch, ovr1 set: data = 0x%x", data);    

#100ns
addr = 32'h00000004;
data = 32'b0;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("2nd read ADC1 peak latch: data = %d", data);    

#100ns
addr = 32'h00000008;
data = 32'b0;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("2nd read ADC2 peak latch: data = %d", data);    
    
@(posedge aclk);
#2
overrange2 = 1'b1;
ADC2data = 7;
@(posedge aclk);
#2
overrange2 = 1'b0;
ADC2data = 3;
@(posedge aclk);
#2
ADC2data=-15;
@(posedge aclk);
#2
ADC2data=31031;
@(posedge aclk);
#2
ADC2data = -30000;
@(posedge aclk);
#2
ADC2data=-32516;
@(posedge aclk);
#2
ADC2data=0;
@(posedge aclk);



#100ns
// read overflow then ADC registers:
addr = 32'h00000000;
data = 32'b0;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("3nd read ADC overrange latch, ovr2 set: data = 0x%x", data);    

#100ns
addr = 32'h00000004;
data = 32'b0;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("3rd read ADC1 peak latch: data = %d", data);    

#100ns
addr = 32'h00000008;
data = 32'b0;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("3rd read ADC2 peak latch: data = %d", data);    
   
     
end

endmodule
