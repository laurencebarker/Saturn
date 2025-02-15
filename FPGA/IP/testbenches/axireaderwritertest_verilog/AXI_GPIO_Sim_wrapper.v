//Copyright 1986-2019 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2019.2 (win64) Build 2708876 Wed Nov  6 21:40:23 MST 2019
//Date        : Tue Jun  8 20:53:22 2021
//Host        : NewDesktop running 64-bit major release  (build 9200)
//Command     : generate_target AXI_GPIO_Sim_wrapper.bd
//Design      : AXI_GPIO_Sim_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module AXI_GPIO_Sim_wrapper
   (aclk,
    aresetn,
    rd_count,
    wr_count,
    tx_enable);
  input aclk;
  input aresetn;
  output [15:0]rd_count;
  output [15:0]wr_count;
  output tx_enable;

  wire aclk;
  wire aresetn;
  wire [15:0]rd_count;
  wire [15:0]wr_count;
  wire       tx_enable;

  AXI_GPIO_Sim AXI_GPIO_Sim_i
       (.aclk(aclk),
        .aresetn(aresetn),
        .rd_count(rd_count),
        .wr_count(wr_count),
        .tx_enable(tx_enable));
endmodule
