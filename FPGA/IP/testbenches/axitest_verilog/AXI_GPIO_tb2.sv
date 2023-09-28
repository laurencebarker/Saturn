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

module AXI_GPIO_tb( );

AXI_GPIO_Sim_wrapper UUT
(
    .aclk               (aclk),
    .aresetn            (aresetn),
    .MISO                (MISO),
    .MOSI                (MOSI),
    .SCLK                (SCLK),
    .nCS                 (nCS),
    .int1_out             (int1_out),
    .fifo1_overflow       (fifo1_overflow),
    .fifo1_count          (fifo1_count),
    .int2_out             (int2_out),
    .fifo2_overflow       (fifo2_overflow),
    .fifo2_count          (fifo2_count),
    .int3_out             (int3_out),
    .fifo3_overflow       (fifo3_overflow),
    .fifo3_count          (fifo3_count),
    .int4_out             (int4_out),
    .fifo4_overflow       (fifo4_overflow),
    .fifo4_count          (fifo4_count),
    .overrange1           (overrange1),
    .overrange2           (overrange2),
    .TX_Strobe            (TX_Strobe),
    .SPI_data             (SPI_data),
    .SPI_ck               (SPI_ck),
    .Rx_load_strobe       (Rx_load_strobe),
    .Tx_load_strobe       (Tx_load_strobe),
    .test_fifo_tdata      (test_fifo_tdata),
    .test_fifo_tvalid     (test_fifo_tvalid),
    .fifo_tready          (fifo_tready)

);

// Generate the clock : 50 MHz    
always #10ns aclk = ~aclk;

//////////////////////////////////////////////////////////////////////////////////
// Main Process
//////////////////////////////////////////////////////////////////////////////////
//
initial begin
    //Assert the reset
    fifo1_overflow = 0;
    fifo2_overflow = 0;
    fifo3_overflow = 0;
    fifo4_overflow = 0;
    aresetn = 0;
    overrange1=0;
    overrange2=0;
    MISO=1;
    test_fifo_tvalid = 0;
    test_fifo_tdata = 0;
    fifo_tready=0;
    #340ns
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
    
    
    //Wait for the reset to be released
    wait (aresetn == 1'b1);
	#200ns
	

/////////////////////////////////////////////////////////////////////////////////////
//
// now test the FIFO monitor
// write control reg1-4; then read them back
#100ns
addr = 32'h00030010;
data = 32'hC0000200;        // FIFO threshold =512, int enabled, read FIFO
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);

#100ns
addr = 32'h00030014;
data = 32'h80000200;        // FIFO threshold =512, int enabled, read FIFO
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);

#100ns
addr = 32'h00030018;
data = 32'h80003000;        // FIFO threshold =0x3000, is enabled, read FIFO
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);

#100ns
addr = 32'h0003001C;
data = 32'h80004000;        // FIFO threshold =0x4000, is enabled, read FIFO
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);

#200ns
data = 32'b0;
addr = 32'h00030010;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read FIFO monitor control reg 1: data = 0x%x", data);

#100ns
data = 32'b0;
addr = 32'h00030014;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read FIFO monitor control reg 2: data = 0x%x", data);

#200ns
data = 32'b0;
addr = 32'h00030018;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read FIFO monitor control reg 3: data = 0x%x", data);

#200ns
data = 32'b0;
addr = 32'h0003001C;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read FIFO monitor control reg 4: data = 0x%x", data);
$display("writing 10 bytes to FIFO 1");

//
// give the FIFOs some data then read the status registers
// give them a FIFO overflow, but on 3&4 remove the overflow before the read to check it is cancelled
// write 10 bytes to the test FIFO
#200ns
 fifo3_count=16'h003ff;                   // give it some data
 fifo3_overflow=1'b1;                    // make it overflow
 fifo4_count=16'h004ff;                   // give it some data
 fifo4_overflow=1'b1;                    // make it overflow
 test_fifo_tdata = 8'hbc;
 test_fifo_tvalid = 1;
#200ns
 fifo3_overflow=1'b0;                    // clear overflow
 fifo4_overflow=1'b0;                    // clear overflow
 test_fifo_tvalid = 0;
#100ns
// they should also show overflows, but 3&4 should drop their interrupt.

addr = 32'h00030000;        // status register
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read FIFO monitor status 1 reg: data = 0x%x", data);
#100ns
addr = 32'h00030004;        // status register
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read FIFO monitor status 2 reg: data = 0x%x", data);

$display("reading 5 bytes from FIFO 1");

//
// assert fifo_tready
 fifo_tready = 1;
#100ns
 fifo_tready = 0;
#100ns
addr = 32'h00030000;        // status register
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("(should be 5) read FIFO monitor status 1 reg: data = 0x%x", data);

$display("reading 5 bytes from FIFO 1 then write one byte back");

//
// assert fifo_tready to read
 fifo_tready = 1;
#100ns
 fifo_tready = 0;
#100ns
 test_fifo_tvalid = 1;
#20ns
 test_fifo_tvalid = 0;
addr = 32'h00030000;        // status register
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("(should be 1 with underflow) read FIFO monitor status 1 reg: data = 0x%x", data);

addr = 32'h00030000;        // status register
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("(should be 1) read FIFO monitor status 1 reg: data = 0x%x", data);


$display ("fill FIFO to 510 samples");
 test_fifo_tvalid = 1;
#10200ns
 test_fifo_tvalid = 0;

@(posedge aclk)
addr = 32'h00030000;        // status register
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("(should be 510) read FIFO monitor status 1 reg: data = 0x%x", data);

$display ("add 2 to 512 samples then read one");
 test_fifo_tvalid = 1;
@(posedge aclk)
@(posedge aclk)

 test_fifo_tvalid = 0;
@(posedge aclk)
 fifo_tready=1;
@(posedge aclk)
 fifo_tready=0;
addr = 32'h00030000;        // status register
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("(should be 511 with overflow) read FIFO monitor status 1 reg: data = 0x%x", data);

addr = 32'h00030000;        // status register
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("(should be 511) read FIFO monitor status 1 reg: data = 0x%x", data);

////////////////////////////////////////////////////////////////////////////////
//
// ADC overrange latch
    
#100ns
addr = 32'h00050000;
data = 32'b0;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("initial read ADC overrange latch: data = 0x%x", data);    

#50ns
overrange1 = 1'b1;
#50ns
overrange1 = 1'b0;
#100ns
addr = 32'h00050000;
data = 32'b0;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("2nd read ADC overrange latch, ovr1 set: data = 0x%x", data);    
    
#50ns
overrange2 = 1'b1;
#50ns
overrange2 = 1'b0;
#100ns
addr = 32'h00050000;
data = 32'b0;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("3nd read ADC overrange latch, ovr2 set: data = 0x%x", data);    
   
/////////////////////////////////////////////////////////////////////////////////////
//
// now test the SPI ADC reader
// write control reg1-4; then read them back
#100ns
addr = 32'h00020000;
data = 32'b0;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read SPI ADC read register, AIN1: data = 0x%x", data);    
   
#100ns
addr = 32'h00020004;
data = 32'b0;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read SPI ADC read register, AIN2: data = 0x%x", data);    
     
#100ns
addr = 32'h00020008;
data = 32'b0;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read SPI ADC read register, AIN3: data = 0x%x", data);    
     
#100ns
addr = 32'h0002000C;
data = 32'b0;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read SPI ADC read register, AIN4: data = 0x%x", data);    
     
#100ns
addr = 32'h00020010;
data = 32'b0;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read SPI ADC read register, AIN5: data = 0x%x", data);    
     
#100ns
addr = 32'h00020014;
data = 32'b0;
master_agent.AXI4LITE_READ_BURST(base_addr + addr,0,data,resp);
$display("read SPI ADC read register, AIN6: data = 0x%x", data);    

///////////////////////////////////////////////////////////////////////////////
//
// AXI Alex Writer
//
$display("AXILite Alex data writer test");    
$display("writing 0x55FF to TX data register");
#100ns
addr = 32'h00040000;
data = 32'h000055FF;
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);

#60us
$display("writing 0x5500FF00 to RX data register");
addr = 32'h00040004;
data = 32'h5500FF00;
master_agent.AXI4LITE_WRITE_BURST(base_addr + addr,0,data,resp);

#60us
$display("setting TX strobe");
TX_Strobe=1;

     
end

endmodule
