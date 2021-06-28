//Copyright 1986-2019 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2019.2 (win64) Build 2708876 Wed Nov  6 21:40:23 MST 2019
//Date        : Sat Jun 12 19:55:47 2021
//Host        : NewDesktop running 64-bit major release  (build 9200)
//Command     : generate_target AXI_GPIO_Sim_wrapper.bd
//Design      : AXI_GPIO_Sim_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module AXI_GPIO_Sim_wrapper
   (aclk,
    aresetn,
    config_reg0,
    config_reg1);
  input aclk;
  input aresetn;
  output [31:0]config_reg0;
  output [31:0]config_reg1;

  wire aclk;
  wire aresetn;
  wire [31:0]config_reg0;
  wire [31:0]config_reg1;

  AXI_GPIO_Sim AXI_GPIO_Sim_i
       (.aclk(aclk),
        .aresetn(aresetn),
        .config_reg0(config_reg0),
        .config_reg1(config_reg1));
endmodule
