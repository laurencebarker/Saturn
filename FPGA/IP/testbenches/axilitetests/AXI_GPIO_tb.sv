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
bit[31:0] config_reg0;
bit[31:0] config_reg1;
bit[31:0] config_reg256_0;
bit[31:0] config_reg256_1;
bit[31:0] config_reg256_2;
bit[31:0] config_reg256_3;
bit[31:0] config_reg256_4;
bit[31:0] config_reg256_5;
bit[31:0] config_reg256_6;
bit[31:0] config_reg256_7;


//AXI4-Lite signals
xil_axi_resp_t 	resp;
bit[31:0]  addr, data, base_addr = 32'h44A0_0000, switch_state;

module AXI_GPIO_tb( );

AXI_GPIO_Sim_wrapper UUT
(
    .aclk               (aclk),
    .aresetn            (aresetn),
    .config_reg0        (config_reg0),
    .config_reg1        (config_reg1),
    .config_reg256_0        (config_reg256_0),
    .config_reg256_1        (config_reg256_1),
    .config_reg256_2        (config_reg256_2),
    .config_reg256_3        (config_reg256_3),
    .config_reg256_4        (config_reg256_4),
    .config_reg256_5        (config_reg256_5),
    .config_reg256_6        (config_reg256_6),
    .config_reg256_7        (config_reg256_7),
    .SPICk                  (SPICk),
    .SPIData                (SPIData),
    .SPILoad_0              (SPILoad_0),
    .SPIMISO                (SPIMISO)
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
    #340ns
    // Release the reset
    aresetn = 1;
end

assign SPIMISO = SPIData;

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
    
    
    //Wait for the reset to be released
    wait (aresetn == 1'b1);
	#200ns
	

/////////////////////////////////////////////////////////////////////////////////////
//
// now test the AXILite read and config write registers
// reasd both 32 bit input registers and check they are zero
$display("testing 64 bit read and config registers");
#100ns
addr = 32'h00001000;
data = 32'h00000000;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite config reg 0 after reset: data = 0x%x", data);

addr = 32'h00001004;
data = 32'h00000000;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite config reg 1 after reset: data = 0x%x", data);

#100ns
addr = 32'h00000000;
data = 32'h00000000;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite read reg 0 after reset: data = 0x%x", data);

addr = 32'h00000004;
data = 32'h00000000;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite read reg 1 after reset: data = 0x%x", data);

// now write the AXILite config write registers
// and read them back

#100ns
addr = 32'h00001000;
data = 32'h01234567;
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);
addr = 32'h00001004;
data = 32'hdeadbeef;
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);

// reading then back
addr = 32'h00001000;
data = 32'h00000000;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite config reg 0 after write: data = 0x%x", data);

addr = 32'h00001004;
data = 32'h00000000;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite config reg 1 after write: data = 0x%x", data);

// now read the status registers, which shouldf have the same data
#100ns
addr = 32'h00000000;
data = 32'h00000000;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite read reg 0 after data write: data = 0x%x", data);

addr = 32'h00000004;
data = 32'h00000000;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite read reg 1 after data write: data = 0x%x", data);




// now test the config 256 write registers - check zero after reset
#100ns
addr = 32'h00002000;
data = 32'h00000000;
$display("testing the config256 register");
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite config256 reg 0 after reset: data = 0x%x", data);
#100ns
addr = 32'h00002004;
data = 32'h00000000;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite config256 reg 1 after reset: data = 0x%x", data);

#100ns
addr = 32'h00002008;
data = 32'h00000000;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite config256 reg 2 after reset: data = 0x%x", data);

#100ns
addr = 32'h0000200C;
data = 32'h00000000;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite config256 reg 3 after reset: data = 0x%x", data);

#100ns
addr = 32'h00002010;
data = 32'h00000000;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite config256 reg 4 after reset: data = 0x%x", data);

#100ns
addr = 32'h00002014;
data = 32'h00000000;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite config256 reg 5 after reset: data = 0x%x", data);

#100ns
addr = 32'h00002018;
data = 32'h00000000;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite config256 reg 6 after reset: data = 0x%x", data);

#100ns
addr = 32'h0000201C;
data = 32'h00000000;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite config256 reg 7 after reset: data = 0x%x", data);


// now test the config 256 write registers - write values
#100ns
addr = 32'h00002000;
data = 32'h0000dead;
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);
#100ns
addr = 32'h00002004;
data = 32'h1111beef;
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);
#100ns
addr = 32'h00002008;
data = 32'h2222dead;
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);
#100ns
addr = 32'h0000200C;
data = 32'h3333beef;
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);
#100ns
addr = 32'h00002010;
data = 32'h4444dead;
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);
#100ns
addr = 32'h00002014;
data = 32'h5555beef;
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);
#100ns
addr = 32'h00002018;
data = 32'h6666dead;
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);
#100ns
addr = 32'h0000201C;
data = 32'h7777beef;
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);
#100ns
$display("data from axi-lite config256 reg 0 after write: data = 0x%x", config_reg256_0);
$display("data from axi-lite config256 reg 1 after write: data = 0x%x", config_reg256_1);
$display("data from axi-lite config256 reg 2 after write: data = 0x%x", config_reg256_2);
$display("data from axi-lite config256 reg 3 after write: data = 0x%x", config_reg256_3);
$display("data from axi-lite config256 reg 4 after write: data = 0x%x", config_reg256_4);
$display("data from axi-lite config256 reg 5 after write: data = 0x%x", config_reg256_5);
$display("data from axi-lite config256 reg 6 after write: data = 0x%x", config_reg256_6);
$display("data from axi-lite config256 reg 7 after write: data = 0x%x", config_reg256_7);

// finally read the registers themselves
$display("reading from axi-lite config256 registers:");
#100ns
addr = 32'h00002000;
data = 32'h00000000;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite config256 reg 0 after write: data = 0x%x", data);
#100ns
addr = 32'h00002004;
data = 32'h00000000;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite config256 reg 1 after write: data = 0x%x", data);

#100ns
addr = 32'h00002008;
data = 32'h00000000;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite config256 reg 2 after write: data = 0x%x", data);

#100ns
addr = 32'h0000200C;
data = 32'h00000000;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite config256 reg 3 after write: data = 0x%x", data);

#100ns
addr = 32'h00002010;
data = 32'h00000000;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite config256 reg 4 after write: data = 0x%x", data);

#100ns
addr = 32'h00002014;
data = 32'h00000000;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite config256 reg 5 after write: data = 0x%x", data);

#100ns
addr = 32'h00002018;
data = 32'h00000000;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite config256 reg 6 after write: data = 0x%x", data);

#100ns
addr = 32'h0000201C;
data = 32'h00000000;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite config256 reg 7 after write: data = 0x%x", data);


////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

//
// now test the AXILite shift register
// 
$display("testing AXILite SPI shift registers");
$display("2 SPI WRITE operations. 2nd will stall on AXI bus until 1st complete");
$display("expecting stall on 2nd write until 1st shift completes");
#100ns
addr = 32'h00003000;
data = 32'h00000c01;
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);
$display("axi-lite SPI write: data = 0x%x", data);
#100ns
addr = 32'h00003000;
data = 32'h0000beef;
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);
$display("axi-lite SPI write: data = 0x%x", data);
#100ns
addr = 32'h00003008;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite SPI writer status while busy: data = 0x%x", data);

#10us                               // wait for write to complete
addr = 32'h00003004;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite SPI read data after 2nd write:: data = 0x%x", data);
//
// gap, then 3 SPI shifts in quick succession
//
#10us
addr = 32'h00003000;
data = 32'h00001112;
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);
$display("axi-lite SPI write: data = 0x%x", data);
#100ns
addr = 32'h00003000;
data = 32'h00002224;
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);
$display("axi-lite SPI write: data = 0x%x", data);
#100ns
addr = 32'h00003000;
data = 32'h00003336;
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);
$display("axi-lite SPI write: data = 0x%x", data);
#100ns
addr = 32'h00003000;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite SPI writer reg 0 after write: data = 0x%x", data);
#100ns
addr = 32'h00003004;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite SPI read dats after 3rd write: data = 0x%x", data);

#10us
addr = 32'h00003008;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read axi-lite SPI writer status after write: data = 0x%x", data);





     
end

endmodule
