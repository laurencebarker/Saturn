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
import IQCODECBLK_axi_vip_0_0_pkg::*;




module IQModnCodec_tb( );

//////////////////////////////////////////////////////////////////////////////////
// Test Bench Signals
//////////////////////////////////////////////////////////////////////////////////
// Clock and Reset
reg aclk = 0;
reg aclk12=0;
reg aresetn = 1;
reg aresetn12 = 1;
reg[4:0] aclkcntr=0;

reg cw_key_down;
reg TX_ENABLE;
reg protocol_2;

reg [63:0] TXIQIn_tdata;
reg TXIQIn_tvalid;
wire TXIQIn_tready;

reg Deinterleave;
reg Byteswap;


reg [2:0] Modulation_Setup;
reg IQEnable;
reg Mux_Reset;
reg [31:0] TXTestFreq;
reg TX_Strobe;

//reg [31:0] keyer_config;
// replaced by
reg [7:0] CWPttDelay;
reg [9:0] CWHangTime;
reg [12:0] CWRampLength;
reg CWKeyerEnable;

reg [31:0] CodecConfig;
reg [15:0] SidetoneFreq;
reg [15:0] SidetoneVol;


wire [47:0] m_axis_TXMod_tdata;
wire m_axis_TXMod_tvalid;
wire m_axis_TXMod_tready;

wire [47:0] m_axis_envelope_tdata;
wire m_axis_envelope_tvalid;
reg m_axis_envelope_tready;
            
wire [15:0] m_axis_sidetoneampl_tdata;
wire m_axis_sidetoneampl_tvalid;

wire CWSampleSelect;
wire cw_ptt;
wire [0:0] TX_OUTPUTENABLE;

//
// clockdivider signals
//
wire TCN;
wire ClockOut;


reg base_addr = 32'h0001C000;
reg [31:0] addr;
reg [31:0] data;
xil_axi_resp_t 	resp;


//
// instantiate block design. Note name can't be too long 
// or we get pathnames too long for windows.
//

IQCODECBLK_wrapper UUT
   (
    .Byteswap            (Byteswap),
    .CWHangTime          (CWHangTime),
    .CWKeyerEnable       (CWKeyerEnable),
    .CWPttDelay          (CWPttDelay),
    .CWRampLength        (CWRampLength),
    .CWSampleSelect     (CWSampleSelect),
    .Deinterleave        (Deinterleave),
    .IQEnable            (IQEnable),
    .Modulation_Setup    (Modulation_Setup),
    .TXIQIn_tdata        (TXIQIn_tdata),
    .TXIQIn_tready       (TXIQIn_tready),
    .TXIQIn_tvalid       (TXIQIn_tdata),
    .TXTestFreq          (TXTestFreq),
    .TX_ENABLE           (TX_ENABLE),
    .TX_OUTPUTENABLE     (TX_OUTPUTENABLE),
    .TX_Strobe           (TX_Strobe),
    .aclk                (aclk),
    .aclk12              (aclk12),
    .aresetn             (aresetn),
    .aresetn12           (aresetn12),
    .cw_key_down         (cw_key_down),
    .cw_ptt              (cw_ptt),
    .m_axis_TXMod_tdata         (m_axis_TXMod_tdata),
    .m_axis_TXMod_tvalid        (m_axis_TXMod_tvalid),
    .m_axis_TXMod_tready        (m_axis_TXMod_tready),
    .m_axis_sidetoneampl_tdata  (m_axis_sidetoneampl_tdata),
    .m_axis_sidetoneampl_tvalid (m_axis_sidetoneampl_tvalid),
    .protocol_2                 (protocol_2),
    .Codec_Config               (CodecConfig)
    );
 




//
// instantiate a clock divider to generate TReady
// divide by 640 to get 192KHz for protocol 2 modulation Fs
ClockDivider #(640) Div 
(
    .aclk            (aclk),
    .resetn          (aresetn),
    .ClockOut        (ClockOut),
    .TC              (m_axis_TXMod_tready),
    .TCN             (TCN)
);


 
parameter CLK_PERIOD=8.1380208;              // 122.88MHz
// Generate the clock : 122.88 MHz    
always #(CLK_PERIOD/2) aclk = ~aclk;

// create divided by 10 clock
always @(posedge aclk)
begin
    aclkcntr = aclkcntr+1;
    if (aclkcntr >= 5)
    begin
        aclk12 = ~aclk12;
        aclkcntr = 0;
    end
end


//////////////////////////////////////////////////////////////////////////////////
// Main Process
//////////////////////////////////////////////////////////////////////////////////
//
initial begin
    //Assert the reset
    aresetn = 0;
    aresetn12 = 0;
    #340
    // Release the reset
    aresetn = 1;
    aresetn12 = 1;
end

//////////////////////////////////////////////////////////////////////////////////
// The following part controls the AXI VIP. 
//It follows the "Useful Coding Guidelines and Examples" section from PG267
//////////////////////////////////////////////////////////////////////////////////
//
// Step 3 - Declare the agent for the master VIP
IQCODECBLK_axi_vip_0_0_mst_t      master_agent;


initial begin    

CWRampLength=3840;
CWHangTime = 10;
CWPttDelay=3;
protocol_2=1;
CWKeyerEnable=1;
Modulation_Setup = 3;
Byteswap = 0;
    SidetoneVol = 24000;					// three quarters amplitude
    SidetoneFreq = 682;						// 500Hz
    CodecConfig = (SidetoneVol << 16) | SidetoneFreq;

//key down after 1us;
// key up after 20ms

// Step 4 - Create a new agent
master_agent = new("master vip agent",UUT.IQCODECBLK_i.axi_vip_0.inst.IF);

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
    if(addr <= 3840)
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
cw_key_down=1;
#20000000           // wait to release key
cw_key_down=0;

end
endmodule

