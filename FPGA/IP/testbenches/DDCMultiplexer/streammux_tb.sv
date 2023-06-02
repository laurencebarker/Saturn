`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer:    Laurence Barker G8NJJ
// 
// Create Date: 27.09.2022 20:28:01
// Design Name: axi stream multiplexer
// Module Name: streammux_tb
// Project Name: Saturn
// Target Devices: artix 7
// Tool Versions: 
// Description:  test bench for axi stream multiplexer. Use axi4 stream verification IP.
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


// import verification IP
// the second and third come from the names in the "sources" window with _pkg annotated
import axi4stream_vip_pkg::*;
import testbench_axi4stream_master0_vip_0_pkg::*;             // master 0
import testbench_axi4stream_master1_vip_0_pkg::*;             // master 1
import testbench_axi4stream_master2_vip_0_pkg::*;             // master 2
import testbench_axi4stream_master3_vip_0_pkg::*;             // master 3
import testbench_axi4stream_master4_vip_0_pkg::*;             // master 4
import testbench_axi4stream_master5_vip_0_pkg::*;             // master 5
import testbench_axi4stream_master6_vip_0_pkg::*;             // master 6
import testbench_axi4stream_master7_vip_0_pkg::*;             // master 7
import testbench_axi4stream_master8_vip_0_pkg::*;             // master 8
import testbench_axi4stream_master9_vip_0_pkg::*;             // master 9

import testbench_axi4stream_slave_vip_0_pkg::*;             // slave

module streammux_tb();

// create instances
// this time the names come from the sources window with _mst_t and _slv_t annotated 
  testbench_axi4stream_master0_vip_0_mst_t mst_agent0;
  testbench_axi4stream_master1_vip_0_mst_t mst_agent1;
  testbench_axi4stream_master2_vip_0_mst_t mst_agent2;
  testbench_axi4stream_master3_vip_0_mst_t mst_agent3;
  testbench_axi4stream_master4_vip_0_mst_t mst_agent4;
  testbench_axi4stream_master5_vip_0_mst_t mst_agent5;
  testbench_axi4stream_master6_vip_0_mst_t mst_agent6;
  testbench_axi4stream_master7_vip_0_mst_t mst_agent7;
  testbench_axi4stream_master8_vip_0_mst_t mst_agent8;
  testbench_axi4stream_master9_vip_0_mst_t mst_agent9;
  axi4stream_ready_gen  ready_gen;    
  testbench_axi4stream_slave_vip_0_slv_t slv_agent;
  xil_axi4stream_uint mst_agent_verbosity = 0;   // Master VIP agent verbosity level
  xil_axi4stream_uint slv_agent_verbosity = 0;  // Slave VIP agent verbosity level
  event ev_disable, ev_changedata;

  bit                                     clock;    // Clock signal
  bit                                     reset;    // Reset signal
  bit [31:0]DDCconfigin = 0;
  bit enabledin = 0;
  wire [31:0]DDCconfigout;
  wire activeout;
  wire fiforstnout;

  // instantiate block design
  testbench_wrapper DUT
  (
      .aresetn(reset),
      .aclk(clock),
      .DDCconfig(DDCconfigin),
      .DDCconfigout(DDCconfigout),
      .enabled(enabledin),
      .active(activeout),
      .fiforstn(fiforstnout)
  );

  always #4 clock <= ~clock;

  initial begin
    // declare master and slve VIP instances
    mst_agent0 = new("master vip agent 0",DUT.testbench_i.axi4stream_master0_vip.inst.IF);
    mst_agent1 = new("master vip agent 1",DUT.testbench_i.axi4stream_master1_vip.inst.IF);
    mst_agent2 = new("master vip agent 2",DUT.testbench_i.axi4stream_master2_vip.inst.IF);
    mst_agent3 = new("master vip agent 3",DUT.testbench_i.axi4stream_master3_vip.inst.IF);
    mst_agent4 = new("master vip agent 4",DUT.testbench_i.axi4stream_master4_vip.inst.IF);
    mst_agent5 = new("master vip agent 5",DUT.testbench_i.axi4stream_master5_vip.inst.IF);
    mst_agent6 = new("master vip agent 6",DUT.testbench_i.axi4stream_master6_vip.inst.IF);
    mst_agent7 = new("master vip agent 7",DUT.testbench_i.axi4stream_master7_vip.inst.IF);
    mst_agent8 = new("master vip agent 8",DUT.testbench_i.axi4stream_master8_vip.inst.IF);
    mst_agent9 = new("master vip agent 9",DUT.testbench_i.axi4stream_master9_vip.inst.IF);
    slv_agent = new("slave vip agent",DUT.testbench_i.axi4stream_slave_vip.inst.IF);
    $timeformat (-12, 1, " ps", 1);
    // When bus is in idle, it must drive everything to 0.otherwise it will 
    // trigger false assertion failure from axi_protocol_chekcer
    mst_agent0.vif_proxy.set_dummy_drive_type(XIL_AXI4STREAM_VIF_DRIVE_NONE);
    mst_agent1.vif_proxy.set_dummy_drive_type(XIL_AXI4STREAM_VIF_DRIVE_NONE);
    mst_agent2.vif_proxy.set_dummy_drive_type(XIL_AXI4STREAM_VIF_DRIVE_NONE);
    mst_agent3.vif_proxy.set_dummy_drive_type(XIL_AXI4STREAM_VIF_DRIVE_NONE);
    mst_agent4.vif_proxy.set_dummy_drive_type(XIL_AXI4STREAM_VIF_DRIVE_NONE);
    mst_agent5.vif_proxy.set_dummy_drive_type(XIL_AXI4STREAM_VIF_DRIVE_NONE);
    mst_agent6.vif_proxy.set_dummy_drive_type(XIL_AXI4STREAM_VIF_DRIVE_NONE);
    mst_agent7.vif_proxy.set_dummy_drive_type(XIL_AXI4STREAM_VIF_DRIVE_NONE);
    mst_agent8.vif_proxy.set_dummy_drive_type(XIL_AXI4STREAM_VIF_DRIVE_NONE);
    mst_agent9.vif_proxy.set_dummy_drive_type(XIL_AXI4STREAM_VIF_DRIVE_NONE);
    slv_agent.vif_proxy.set_dummy_drive_type(XIL_AXI4STREAM_VIF_DRIVE_NONE);
    
    // Set tag for agents for easy debug,if not set here, it will be hard to tell which driver is filing 
    // if multiple agents are called in one testbench
    mst_agent0.set_agent_tag("Master 0 VIP");
    mst_agent1.set_agent_tag("Master 1 VIP");
    mst_agent2.set_agent_tag("Master 2 VIP");
    mst_agent3.set_agent_tag("Master 3 VIP");
    mst_agent4.set_agent_tag("Master 4 VIP");
    mst_agent5.set_agent_tag("Master 5 VIP");
    mst_agent6.set_agent_tag("Master 6 VIP");
    mst_agent7.set_agent_tag("Master 7 VIP");
    mst_agent8.set_agent_tag("Master 8 VIP");
    mst_agent9.set_agent_tag("Master 9 VIP");
    slv_agent.set_agent_tag("Slave VIP");

    // set print out verbosity level.
    mst_agent0.set_verbosity(mst_agent_verbosity);
    mst_agent1.set_verbosity(mst_agent_verbosity);
    mst_agent2.set_verbosity(mst_agent_verbosity);
    mst_agent3.set_verbosity(mst_agent_verbosity);
    mst_agent4.set_verbosity(mst_agent_verbosity);
    mst_agent5.set_verbosity(mst_agent_verbosity);
    mst_agent6.set_verbosity(mst_agent_verbosity);
    mst_agent7.set_verbosity(mst_agent_verbosity);
    mst_agent8.set_verbosity(mst_agent_verbosity);
    mst_agent9.set_verbosity(mst_agent_verbosity);
    slv_agent.set_verbosity(slv_agent_verbosity);
//
// set up the ready generator
//

    ready_gen = slv_agent.driver.create_ready("ready_gen");
//    ready_gen.set_ready_policy(XIL_AXI4STREAM_READY_GEN_OSC);
    ready_gen.set_ready_policy(XIL_AXI4STREAM_READY_GEN_NO_BACKPRESSURE);
//    ready_gen.set_low_time(2);
//    ready_gen.set_high_time(6);
    slv_agent.driver.send_tready(ready_gen);

    // Master,slave agents start to run 
    // Turn on passthrough agent monitor 
    mst_agent0.start_master();
    mst_agent1.start_master();
    mst_agent2.start_master();
    mst_agent3.start_master();
    mst_agent4.start_master();
    mst_agent5.start_master();
    mst_agent6.start_master();
    mst_agent7.start_master();
    mst_agent8.start_master();
    mst_agent9.start_master();
    slv_agent.start_slave();
    
    //
    // assert reset for 10 clocks, then release reset
    //
    reset<= 0;
    repeat(20) @(posedge clock);
    reset<=1;
    repeat(5) @(posedge clock);
//
// set active, and DDC2, 6 = 192KHz, others disabled
// DDC word = hex 000C00C0
//    
    enabledin<= 1;
    DDCconfigin <= 32'h000C00C0;          // DDC 2& 6
//    DDCconfigin <= 32'h000C0018;          // DDC 1 & 6
    
    // now initiate data generator and slave monitor
    fork
      master0_generate_data();
      master1_generate_data();
      master2_generate_data();
      master3_generate_data();
      master4_generate_data();
      master5_generate_data();
      master6_generate_data();
      master7_generate_data();
      master8_generate_data();
      master9_generate_data();
      slave_display_data();
      disableeventwatcher();
      changedataeventwatcher();
    join_any
    $finish;
  end


//  task slv_gen_tready();
//    axi4stream_ready_gen                           ready_gen;
//    ready_gen = slv_agent.driver.create_ready("ready_gen");
//    ready_gen.set_ready_policy(XIL_AXI4STREAM_READY_GEN_OSC);
//    ready_gen.set_low_time(2);
//    ready_gen.set_high_time(6);
//    slv_agent.driver.send_tready(ready_gen);
//  endtask :slv_gen_tready


//
// event watcher for change DDC settings
//
  task changedataeventwatcher();
  
  while (1) begin
    @ev_changedata;
    //                 XX999888777666555444333222111000
    DDCconfigin <= 32'b00000001000000011111000100010001;
    $display ("change DDC signalled; 4&5 will now be interleaved; 192KHz (4 samples); DDC8 enabled at 48KHz");
  end
  endtask



//
// event watcher for enough data generated
//
  task disableeventwatcher();
  
  while (1) begin
    @ev_disable;
    enabledin=0;
    $display ("disable mux signalled");
    repeat(1000) @(posedge clock);
    enabledin=1;
  end
  endtask



//
// this task adds data to the master transaction generator for master 0
// this is set to add a preset number of data beats then terminate, 
// ending the simulation.
//
  task master0_generate_data();
    logic [47:0] writedata = 0;
    logic[15:0] samplenum = 0;
    while(samplenum < 255) begin
      axi4stream_transaction wr_transaction = mst_agent0.driver.create_transaction("master VIP write transaction");
      writedata[47:32] = 16'h0000;                      // master number
      writedata[31:16] = 16'hff00;                      // identifyable activeout 
      writedata[15:0] = samplenum;
      wr_transaction.set_data_beat(writedata);
      samplenum = samplenum + 1;
      mst_agent0.driver.send(wr_transaction);
      //
      // check if finished. Trigger event if ready to change data or stop data transfer.
      //
      if(samplenum == 200)
          ->ev_changedata;
      if(samplenum == 300)
          ->ev_disable;
    end
  endtask
  
//
// this task adds data to the master transaction generator for master 1
// this is set to add a preset number of data beats then terminate, 
// ending the simulation.
//
  task master1_generate_data();
    logic [47:0] writedata = 0;
    logic[15:0] samplenum = 0;
    while(samplenum < 255) begin
      axi4stream_transaction wr_transaction = mst_agent1.driver.create_transaction("master VIP write transaction");
      writedata[47:32] = 16'h0011;                      // master number
      writedata[31:16] = 16'hff00;                      // identifyable activeout 
      writedata[15:0] = samplenum;
      wr_transaction.set_data_beat(writedata);
      samplenum = samplenum + 1;
      mst_agent1.driver.send(wr_transaction);
    end
  endtask

//
// this task adds data to the master transaction generator for master 2
// this is set to add a preset number of data beats then terminate, 
// ending the simulation.
//
  task master2_generate_data();
    logic [47:0] writedata = 0;
    logic[15:0] samplenum = 0;
//    mst_agent2.driver.set_transaction_depth(16);
    while(samplenum < 255) begin
        axi4stream_transaction wr_transaction = mst_agent2.driver.create_transaction("master VIP write transaction");
        writedata[47:32] = 16'h0022;                      // master number
        writedata[31:16] = 16'hff00;                      // identifyable activeout 
        writedata[15:0] = samplenum;
        wr_transaction.set_data_beat(writedata);
        samplenum = samplenum + 1;
        mst_agent2.driver.send(wr_transaction);
    end
  endtask

//
// this task adds data to the master transaction generator for master 3
// this is set to add a preset number of data beats then terminate, 
// ending the simulation.
//
  task master3_generate_data();
    logic [47:0] writedata = 0;
    logic[15:0] samplenum = 0;
    while(samplenum < 255) begin
      axi4stream_transaction wr_transaction = mst_agent3.driver.create_transaction("master VIP write transaction");
      writedata[47:32] = 16'h0033;                      // master number
      writedata[31:16] = 16'hff00;                      // identifyable activeout 
      writedata[15:0] = samplenum;
      wr_transaction.set_data_beat(writedata);
      samplenum = samplenum + 1;
      mst_agent3.driver.send(wr_transaction);
    end
  endtask

//
// this task adds data to the master transaction generator for master 4
// this is set to add a preset number of data beats then terminate, 
// ending the simulation.
//
  task master4_generate_data();
    logic [47:0] writedata = 0;
    logic[15:0] samplenum = 0;
    while(samplenum < 255) begin
      axi4stream_transaction wr_transaction = mst_agent4.driver.create_transaction("master VIP write transaction");
      writedata[47:32] = 16'h0044;                      // master number
      writedata[31:16] = 16'hff00;                      // identifyable activeout 
      writedata[15:0] = samplenum;
      wr_transaction.set_data_beat(writedata);
      samplenum = samplenum + 1;
      mst_agent4.driver.send(wr_transaction);
    end
  endtask

//
// this task adds data to the master transaction generator for master 5
// this is set to add a preset number of data beats then terminate, 
// ending the simulation.
//
  task master5_generate_data();
    logic [47:0] writedata = 0;
    logic[15:0] samplenum = 0;
    while(samplenum < 255) begin
      axi4stream_transaction wr_transaction = mst_agent5.driver.create_transaction("master VIP write transaction");
      writedata[47:32] = 16'h0055;                      // master number
      writedata[31:16] = 16'hff00;                      // identifyable activeout 
      writedata[15:0] = samplenum;
      wr_transaction.set_data_beat(writedata);
      samplenum = samplenum + 1;
      mst_agent5.driver.send(wr_transaction);
    end
  endtask

//
// this task adds data to the master transaction generator for master 6
// this is set to add a preset number of data beats then terminate, 
// ending the simulation.
//
  task master6_generate_data();
    logic [47:0] writedata = 0;
    logic[15:0] samplenum = 0;
    while(samplenum < 255) begin
      axi4stream_transaction wr_transaction = mst_agent6.driver.create_transaction("master VIP write transaction");
      writedata[47:32] = 16'h0066;                      // master number
      writedata[31:16] = 16'hff00;                      // identifyable activeout 
      writedata[15:0] = samplenum;
      wr_transaction.set_data_beat(writedata);
      samplenum = samplenum + 1;
      mst_agent6.driver.send(wr_transaction);
    end
  endtask

//
// this task adds data to the master transaction generator for master 7
// this is set to add a preset number of data beats then terminate, 
// ending the simulation.
//
  task master7_generate_data();
    logic [47:0] writedata = 0;
    logic[15:0] samplenum = 0;
    while(samplenum < 255) begin
      axi4stream_transaction wr_transaction = mst_agent7.driver.create_transaction("master VIP write transaction");
      writedata[47:32] = 16'h0077;                      // master number
      writedata[31:16] = 16'hff00;                      // identifyable activeout 
      writedata[15:0] = samplenum;
      wr_transaction.set_data_beat(writedata);
      samplenum = samplenum + 1;
      mst_agent7.driver.send(wr_transaction);
    end
  endtask

//
// this task adds data to the master transaction generator for master 8
// this is set to add a preset number of data beats then terminate, 
// ending the simulation.
//
  task master8_generate_data();
    logic [47:0] writedata = 0;
    logic[15:0] samplenum = 0;
    while(samplenum < 255) begin
      axi4stream_transaction wr_transaction = mst_agent8.driver.create_transaction("master VIP write transaction");
      writedata[47:32] = 16'h0088;                      // master number
      writedata[31:16] = 16'hff00;                      // identifyable activeout 
      writedata[15:0] = samplenum;
      wr_transaction.set_data_beat(writedata);
      samplenum = samplenum + 1;
      mst_agent8.driver.send(wr_transaction);
    end
  endtask

//
// this task adds data to the master transaction generator for master 9
// this is set to add a preset number of data beats then terminate, 
// ending the simulation.
//
  task master9_generate_data();
    logic [47:0] writedata = 0;
    logic[15:0] samplenum = 0;
    while(samplenum < 255) begin
      axi4stream_transaction wr_transaction = mst_agent9.driver.create_transaction("master VIP write transaction");
      writedata[47:32] = 16'h0099;                      // master number
      writedata[31:16] = 16'hff00;                      // identifyable activeout 
      writedata[15:0] = samplenum;
      wr_transaction.set_data_beat(writedata);
      samplenum = samplenum + 1;
      mst_agent9.driver.send(wr_transaction);
    end
  endtask


  //
  // this task pulls data from the slave VIP and displays in the TCL window
  // output data is 64 bits
  task slave_display_data();
    axi4stream_monitor_transaction slv_monitor_transaction;
    xil_axi4stream_data_byte InputData[8];

    while(1) begin
      slv_agent.monitor.item_collected_port.get(slv_monitor_transaction);
      slv_monitor_transaction.get_data(InputData);
      $display("Slave received Transaction data: %2x%2x %2x%2x %2x%2x %2x%2x", InputData[7], InputData[6],InputData[5],InputData[4],InputData[3],InputData[2],InputData[1],InputData[0]);
    end
  endtask




endmodule
