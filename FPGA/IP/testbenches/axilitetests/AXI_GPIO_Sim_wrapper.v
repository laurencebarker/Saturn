//Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2021.2 (win64) Build 3367213 Tue Oct 19 02:48:09 MDT 2021
//Date        : Fri Aug  5 03:18:07 2022
//Host        : Loz-Inspiron running 64-bit major release  (build 9200)
//Command     : generate_target AXI_GPIO_Sim_wrapper.bd
//Design      : AXI_GPIO_Sim_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module AXI_GPIO_Sim_wrapper
   (SPICk,
    SPIData,
    SPILoad_0,
    SPIMISO,
    aclk,
    aresetn,
    config_reg0,
    config_reg1,
    config_reg256_0,
    config_reg256_1,
    config_reg256_2,
    config_reg256_3,
    config_reg256_4,
    config_reg256_5,
    config_reg256_6,
    config_reg256_7);
  output SPICk;
  output SPIData;
  output SPILoad_0;
  input SPIMISO;
  input aclk;
  input aresetn;
  output [31:0]config_reg0;
  output [31:0]config_reg1;
  output [31:0]config_reg256_0;
  output [31:0]config_reg256_1;
  output [31:0]config_reg256_2;
  output [31:0]config_reg256_3;
  output [31:0]config_reg256_4;
  output [31:0]config_reg256_5;
  output [31:0]config_reg256_6;
  output [31:0]config_reg256_7;

  wire SPICk;
  wire SPIData;
  wire SPILoad_0;
  wire SPIMISO;
  wire aclk;
  wire aresetn;
  wire [31:0]config_reg0;
  wire [31:0]config_reg1;
  wire [31:0]config_reg256_0;
  wire [31:0]config_reg256_1;
  wire [31:0]config_reg256_2;
  wire [31:0]config_reg256_3;
  wire [31:0]config_reg256_4;
  wire [31:0]config_reg256_5;
  wire [31:0]config_reg256_6;
  wire [31:0]config_reg256_7;

  AXI_GPIO_Sim AXI_GPIO_Sim_i
       (.SPICk(SPICk),
        .SPIData(SPIData),
        .SPILoad_0(SPILoad_0),
        .SPIMISO(SPIMISO),
        .aclk(aclk),
        .aresetn(aresetn),
        .config_reg0(config_reg0),
        .config_reg1(config_reg1),
        .config_reg256_0(config_reg256_0),
        .config_reg256_1(config_reg256_1),
        .config_reg256_2(config_reg256_2),
        .config_reg256_3(config_reg256_3),
        .config_reg256_4(config_reg256_4),
        .config_reg256_5(config_reg256_5),
        .config_reg256_6(config_reg256_6),
        .config_reg256_7(config_reg256_7));
endmodule
