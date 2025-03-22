`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:        HPSDR
// Engineer:       Laurence Barker G8NJJ
// 
// Create Date:    07.05.2021 16:42:01
// Design Name:    stream_reader_writer testbench
// Module Name:    AXI_Stream_Reader_Writer
// Project Name:   Saturn
// Target Devices: Artix 7
// Tool Versions:  Vivado
// Description:    Testbench to Write and read AXI-4 Streams from an AXI4 slave interfasce
//                 The AXI address is ignored, so this works with a DMA
//                 with incrementing address that writes from the one port. 
//
//                 This is a core in two halves: a stream writer and a stream reader.
//
//                 Using the AVI verification IP - see example from its example design
//                 look at the testbench for sim_all_config
//                 Note the testbench file will show errors (red underline)
//                 but it compiles and works. This seems to be a known issue.
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


// Import two required packages: axi_vip_pkg and <component_name>_pkg.

import axi_vip_pkg::*;
import AXI_GPIO_Sim_axi_vip_0_0_pkg::*;



//////////////////////////////////////////////////////////////////////////////////
// Test Bench Signals
//////////////////////////////////////////////////////////////////////////////////
// Clock and Reset
bit aclk = 0, aresetn = 1;

//Simulation output - FIFO read and write depth
bit [15:0] wr_count;
bit [15:0] rd_count;
bit        tx_enable;


//AXI4 bus signals
bit[31:0]  offset_addr, base_addr = 32'h44A0_0000;
xil_axi_uint                mtestID;
xil_axi_ulong               mtestADDR;
xil_axi_len_t               mtestBurstLength= 'd4;
xil_axi_size_t              mtestDataSize=xil_axi_size_t'(xil_clog2((32)/8));
xil_axi_burst_t             mtestBurstType =  XIL_AXI_BURST_TYPE_INCR;
xil_axi_lock_t              mtestLOCK = XIL_AXI_ALOCK_NOLOCK;
xil_axi_cache_t             mtestCacheType = 3;
xil_axi_prot_t              mtestProtectionType=0;
xil_axi_region_t            mtestRegion=0;
xil_axi_qos_t               mtestQOS=0;
xil_axi_data_beat           dbeat;
xil_axi_user_beat           usrbeat;
xil_axi_data_beat [31:0]    mtestWUSER;
xil_axi_data_beat           mtestAWUSER = 'h0;
xil_axi_data_beat           mtestARUSER = 0;
xil_axi_data_beat [31:0]    mtestRUSER;
xil_axi_uint                mtestBUSER = 0;
xil_axi_resp_t              mtestBresp;
xil_axi_resp_t[31:0]        mtestRresp;

bit [31:0]                  mtestWData = 32'h12345678, mtestWData1 = 32'h87654321, mtestWData2 = 32'h00005678,   mtestWData3 = 32'h1234000;
bit [32767:0]                           mtestWDataBlock;
bit [32767:0]                           mtestRDataBlock;


bit [31:0]                  mtestRData;


module AXI_GPIO_tb( );



AXI_GPIO_Sim_wrapper UUT
(
    .aclk               (aclk),
    .aresetn            (aresetn),
    .wr_count     (wr_count),
    .rd_count     (rd_count),
    .tx_enable    (tx_enable)
);

// Generate the clock : 50 MHz    
always #10ns aclk = ~aclk;

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
//
//////////////////////////////////////////////////////////////////////////////////
// The following part controls the AXI VIP. 
//It follows the "Usefull Coding Guidelines and Examples" section from PG267
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
	
    
////////////////////////////////////////////////////////////////////////////////
//
// now test the stream reader/writer
// write 3 64 bit words, which should go into FIFO; then read 3 words.
//


#200ns
mtestID = 0;
mtestADDR = 32'h44A0_0000;
mtestBurstLength = 'd2;                     // 3 beats each 32 bits
mtestWDataBlock[31:0] = 32'hdeadbeef;
mtestWDataBlock[63:32] = 32'hbeef0001;
mtestWDataBlock[95:64] = 32'hdead0002;

$display("1st write (3 beats) to stream reader/writer: data = 0x%x", mtestWData);    
master_agent.AXI4_WRITE_BURST(
        mtestID,
        mtestADDR,
        mtestBurstLength,
        mtestDataSize,
        mtestBurstType,
        mtestLOCK,
        mtestCacheType,
        mtestProtectionType,
        mtestRegion,
        mtestQOS,
        mtestAWUSER,
        mtestWDataBlock,
        mtestWUSER,
        mtestBresp
      );  

mtestBurstLength = 'd0;                     // 1 beat
mtestWData = 32'hace80003;
$display("2nd write (1 beat) to stream reader/writer: data = 0x%x", mtestWData);    
master_agent.AXI4_WRITE_BURST(
        mtestID,
        mtestADDR,
        mtestBurstLength,
        mtestDataSize,
        mtestBurstType,
        mtestLOCK,
        mtestCacheType,
        mtestProtectionType,
        mtestRegion,
        mtestQOS,
        mtestAWUSER,
        mtestWData,
        mtestWUSER,
        mtestBresp
      );  

mtestBurstLength = 'd1;                     // 2 beats each 32 bits
mtestWDataBlock[31:0] = 32'habc00004;
mtestWDataBlock[63:32] = 32'hdef00005;

$display("3rd write (2 beats) to stream reader/writer: data = 0x%x", mtestWData);    
master_agent.AXI4_WRITE_BURST(
        mtestID,
        mtestADDR,
        mtestBurstLength,
        mtestDataSize,
        mtestBurstType,
        mtestLOCK,
        mtestCacheType,
        mtestProtectionType,
        mtestRegion,
        mtestQOS,
        mtestAWUSER,
        mtestWDataBlock,
        mtestWUSER,
        mtestBresp
      );  




#10us
$display("after write: Read_Count = 0x%x", rd_count);    
$display("after write: Write_Count = 0x%x", wr_count);    

#100ns
mtestBurstLength = 'd0;                     // 1 beat read
master_agent.AXI4_READ_BURST(
mtestID,
mtestADDR,
mtestBurstLength,
mtestDataSize,
mtestBurstType,
mtestLOCK,
mtestCacheType,
mtestProtectionType,
mtestRegion,
mtestQOS,
mtestARUSER,
mtestRData,
mtestRresp,
mtestRUSER
);
$display("1st 32bit read stream reader/writer: data = 0x%x", mtestRData);    


                     // 1 beat read
master_agent.AXI4_READ_BURST(
mtestID,
mtestADDR,
mtestBurstLength,
mtestDataSize,
mtestBurstType,
mtestLOCK,
mtestCacheType,
mtestProtectionType,
mtestRegion,
mtestQOS,
mtestARUSER,
mtestRData,
mtestRresp,
mtestRUSER
);
$display("2nd 32bit read stream reader/writer: data = 0x%x", mtestRData);    


mtestBurstLength = 'd1;                     // 2 beats read
master_agent.AXI4_READ_BURST(
mtestID,
mtestADDR,
mtestBurstLength,
mtestDataSize,
mtestBurstType,
mtestLOCK,
mtestCacheType,
mtestProtectionType,
mtestRegion,
mtestQOS,
mtestARUSER,
mtestRDataBlock,
mtestRresp,
mtestRUSER
);
$display("3rd 64bit read stream reader/writer: data = 0x%x", mtestRDataBlock[63:0]);    

mtestBurstLength = 'd1;                     // 2 beats read
master_agent.AXI4_READ_BURST(
mtestID,
mtestADDR,
mtestBurstLength,
mtestDataSize,
mtestBurstType,
mtestLOCK,
mtestCacheType,
mtestProtectionType,
mtestRegion,
mtestQOS,
mtestARUSER,
mtestRDataBlock,
mtestRresp,
mtestRUSER
);
$display("4th 64 bit read stream reader/writer: data = 0x%x", mtestRDataBlock[63:0]);    

#200ns
$display("after read: Read_Count = 0x%x", rd_count);    
$display("after read: Write_Count = 0x%x", wr_count);    
#200ns


//
// now do it all again
//
#100us

mtestID = 0;
mtestADDR = 32'h44A0_0000;
mtestBurstLength = 'd2;                     // 3 beats
mtestWDataBlock[31:0] = 32'hdeadbeef;
mtestWDataBlock[63:32] = 32'hbeef0001;
mtestWDataBlock[95:64] = 32'hdead0002;

$display("1st write (3 beats) to stream reader/writer: data = 0x%x", mtestWData);    
master_agent.AXI4_WRITE_BURST(
        mtestID,
        mtestADDR,
        mtestBurstLength,
        mtestDataSize,
        mtestBurstType,
        mtestLOCK,
        mtestCacheType,
        mtestProtectionType,
        mtestRegion,
        mtestQOS,
        mtestAWUSER,
        mtestWDataBlock,
        mtestWUSER,
        mtestBresp
      );  

$display("2nd write (1 beat) to stream reader/writer: data = 0x%x", mtestWData);    
mtestBurstLength = 'd0;                     // 1 beat
mtestWData = 32'hace80003;
master_agent.AXI4_WRITE_BURST(
        mtestID,
        mtestADDR,
        mtestBurstLength,
        mtestDataSize,
        mtestBurstType,
        mtestLOCK,
        mtestCacheType,
        mtestProtectionType,
        mtestRegion,
        mtestQOS,
        mtestAWUSER,
        mtestWData,
        mtestWUSER,
        mtestBresp
      );  

mtestBurstLength = 'd1;                     // 2 beats each 32 bits
mtestWDataBlock[31:0] = 32'habc00004;
mtestWDataBlock[63:32] = 32'hdef00005;

$display("3rd write (2 beats) to stream reader/writer: data = 0x%x", mtestWData);    
master_agent.AXI4_WRITE_BURST(
        mtestID,
        mtestADDR,
        mtestBurstLength,
        mtestDataSize,
        mtestBurstType,
        mtestLOCK,
        mtestCacheType,
        mtestProtectionType,
        mtestRegion,
        mtestQOS,
        mtestAWUSER,
        mtestWDataBlock,
        mtestWUSER,
        mtestBresp
      );  

#10us
$display("after write: Read_Count = 0x%x", rd_count);    
$display("after write: Write_Count = 0x%x", wr_count);    

#100ns
mtestBurstLength = 'd0;                     // 1 beat
master_agent.AXI4_READ_BURST(
mtestID,
mtestADDR,
mtestBurstLength,
mtestDataSize,
mtestBurstType,
mtestLOCK,
mtestCacheType,
mtestProtectionType,
mtestRegion,
mtestQOS,
mtestARUSER,
mtestRData,
mtestRresp,
mtestRUSER
);
$display("1st 32bit read stream reader/writer: data = 0x%x", mtestRData);    


master_agent.AXI4_READ_BURST(
mtestID,
mtestADDR,
mtestBurstLength,
mtestDataSize,
mtestBurstType,
mtestLOCK,
mtestCacheType,
mtestProtectionType,
mtestRegion,
mtestQOS,
mtestARUSER,
mtestRData,
mtestRresp,
mtestRUSER
);
$display("2nd 32bit read stream reader/writer: data = 0x%x", mtestRData);    


mtestBurstLength = 'd1;                     // 2 beats
master_agent.AXI4_READ_BURST(
mtestID,
mtestADDR,
mtestBurstLength,
mtestDataSize,
mtestBurstType,
mtestLOCK,
mtestCacheType,
mtestProtectionType,
mtestRegion,
mtestQOS,
mtestARUSER,
mtestRDataBlock,
mtestRresp,
mtestRUSER
);
$display("3rd 64bit read stream reader/writer: data = 0x%x", mtestRDataBlock[63:0]);    

mtestBurstLength = 'd1;                     // 2 beats read
master_agent.AXI4_READ_BURST(
mtestID,
mtestADDR,
mtestBurstLength,
mtestDataSize,
mtestBurstType,
mtestLOCK,
mtestCacheType,
mtestProtectionType,
mtestRegion,
mtestQOS,
mtestARUSER,
mtestRDataBlock,
mtestRresp,
mtestRUSER
);
$display("4th 64 bit read stream reader/writer: data = 0x%x", mtestRDataBlock[63:0]);    


$display("after read: Read_Count = 0x%x", rd_count);    
$display("after read: Write_Count = 0x%x", wr_count);    




end

endmodule
