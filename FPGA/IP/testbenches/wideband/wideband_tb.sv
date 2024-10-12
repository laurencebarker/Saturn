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
// Filename:        wideband_tb.sv
// Version:         v1.0
// Description:     Simulation test bench for wideband IP
//                  
//-----------------------------------------------------------------------------
//Step 2 - Import two required packages: axi_vip_pkg and <component_name>_pkg.
// second one is a filename from build tree: 
// <blockdiagrambame><AXI test instance name>_0_pkg
import axi_vip_pkg::*;
import widebandtest_axi_vip_0_0_pkg::*;



//////////////////////////////////////////////////////////////////////////////////
// Test Bench Signals
//////////////////////////////////////////////////////////////////////////////////
// Clock and Reset
bit aclk = 0, aresetn = 1;


//AXI4-Lite signals
xil_axi_resp_t 	resp;
bit[31:0]  addr, data, base_addr = 32'h0000_0000, switch_state;

module wideband_tb( );

widebandtest_wrapper UUT
(
    .aclk               (aclk),
    .aresetn            (aresetn)
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
// <blockdiagrambame><AXI test instance name>_0_mst_t
widebandtest_axi_vip_0_0_mst_t      master_agent;

//
initial begin    

// Step 4 - Create a new agent
// UUT.<blockdiagrambame>_i.<AXI test instance name>.inst.IF

master_agent = new("master vip agent",UUT.widebandtest_i.axi_vip_0.inst.IF);

// Step 5 - Start the agent
master_agent.start_master();
    
	#10us
    
    //Wait for the reset to be released
    wait (aresetn == 1'b1);
	#10us
	

/////////////////////////////////////////////////////////////////////////////////////
//
// test the wideband
// write depth and delay registers, then read back all 4 registers
$display("1st phase: initial writes then reads to wideband registers:");
$display("control register = 0;");
$display("period register = 12,500,000;");
$display("depth register = 15 to enable 16 writes;");

#50us
addr = 32'h0000;
data = 32'd0;        // no enables
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);

#100ns
addr = 32'h0004;
data = 32'd12500000;        // 100ms period
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);

#200ns
addr = 32'h0008;
data = 32'h0000000F;        // write depth = 16
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);

#200ns
data = 32'b0;
addr = 32'h0000;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read wideband control reg: data = 0x%x", data);

#200ns
data = 32'b0;
addr = 32'h0004;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read wideband record period reg: data = (decimal) ", data);

#200ns
data = 32'b0;
addr = 32'h0008;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read wideband depth reg: data = 0x%x", data);

#200ns
data = 32'b0;
addr = 32'h000C;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read wideband status reg: data = 0x%x", data);
//

$display("");
$display("");
$display("test WB acquire from ADC0:");

// write control register to value 1
$display("write wideband control = 1 to enable ADC0:");
addr = 32'h0000;
data = 32'd1;        // enable ADC1
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);
//
// expect to see data collected now!
//
#10us
$display("write operation should be complete");
data = 32'b0;
addr = 32'h000C;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read wideband status reg: data = 0x%x", data);
$display("should have 16 samples, and ADC0 bit set");
$display("write processor data read out bit");
addr = 32'h0000;
data = 32'd5;        // enable ADC1, processor data read
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);


//
// ignore reading out FIFO for now
//
$display("");
$display("");
$display("next phase: disable operation, so WB resets to idle");
$display("write record depth = 32, then enable ADC1 record");
// write control register to value 1
addr = 32'h0000;
data = 32'd0;        // disable
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);

#200ns

addr = 32'h0008;
data = 32'h00000001F;        // write depth = 32
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);

#200ns
// write control register to value 2 to enable ADC1
$display("write wideband control = 2 to enable ADC1:");
addr = 32'h0000;
data = 32'd2;        // enable ADC1
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);


//
// expect to see data collected now!
//
#10us
$display("write operation should be complete");
data = 32'b0;
addr = 32'h000C;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read wideband status reg: data = 0x%x", data);
$display("should have 48 samples, and ADC1 bit set");
$display("write processor data read out bit");
addr = 32'h0000;
data = 32'd6;        // enable ADC2, processor data read
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);

//
// ignore reading out FIFO for now
//



$display("");
$display("next phase: disable operation, so WB resets to idle");
$display("write record depth = 16 again, then enable both ADC1&2 record");
// write control register to value 1
addr = 32'h0000;
data = 32'd0;        // disable
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);

#200ns

addr = 32'h0008;
data = 32'h00000000F;        // write depth = 32
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);

#200ns
// write control register to value 3 to enable both ADC
$display("write wideband control = 3 to enable both ADC:");
addr = 32'h0000;
data = 32'd3;        // enable ADC1 & 0
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);


//
// expect to see data collected now!
//
#10us
$display("ADC0 write operation should be complete");
data = 32'b0;
addr = 32'h000C;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read wideband status reg: data = 0x%x", data);
$display("should have 64 samples, and ADC0 bit set");

$display("write processor data read out bit");
addr = 32'h0000;
data = 32'd7;        // enable both ADC1 processor data read
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);

     
#10us     
$display("ADC1 write operation should be complete");
data = 32'b0;
addr = 32'h000C;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read wideband status reg: data = 0x%x", data);
$display("should have 80 samples, and ADC1 bit set");
     
$display("write processor data read out bit");
addr = 32'h0000;
data = 32'd7;        // enable both ADC, processor data read
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);


     
end

endmodule
