//Copyright 1986-2019 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2019.2 (win64) Build 2708876 Wed Nov  6 21:40:23 MST 2019
//Date        : Wed Jun  9 19:38:44 2021
//Host        : NewDesktop running 64-bit major release  (build 9200)
//Command     : generate_target AXI_GPIO_Sim_wrapper.bd
//Design      : AXI_GPIO_Sim_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module AXI_GPIO_Sim_wrapper
   (MISO,
    MOSI,
    Rx_load_strobe,
    SCLK,
    SPI_ck,
    SPI_data,
    TX_Strobe,
    Tx_load_strobe,
    aclk,
    aresetn,
    fifo1_count,
    fifo1_overflow,
    fifo2_count,
    fifo2_overflow,
    fifo3_count,
    fifo3_overflow,
    fifo4_count,
    fifo4_overflow,
    test_fifo_tvalid,
    test_fifo_tdata,
    int1_out,
    int2_out,
    int3_out,
    int4_out,
    nCS,
    overrange1,
    overrange2);
  input MISO;
  output MOSI;
  output Rx_load_strobe;
  output SCLK;
  output SPI_ck;
  output SPI_data;
  input TX_Strobe;
  output Tx_load_strobe;
  input aclk;
  input aresetn;
  input [15:0]fifo1_count;
  input fifo1_overflow;
  input [15:0]fifo2_count;
  input fifo2_overflow;
  input [15:0]fifo3_count;
  input fifo3_overflow;
  input [15:0]fifo4_count;
  input fifo4_overflow;
  input test_fifo_tvalid;
  input [7:0]test_fifo_tdata;
  output int1_out;
  output int2_out;
  output int3_out;
  output int4_out;
  output nCS;
  input overrange1;
  input overrange2;

  wire MISO;
  wire MOSI;
  wire Rx_load_strobe;
  wire SCLK;
  wire SPI_ck;
  wire SPI_data;
  wire TX_Strobe;
  wire Tx_load_strobe;
  wire aclk;
  wire aresetn;
  wire [15:0]fifo1_count;
  wire fifo1_overflow;
  wire [15:0]fifo2_count;
  wire fifo2_overflow;
  wire [15:0]fifo3_count;
  wire fifo3_overflow;
  wire [15:0]fifo4_count;
  wire fifo4_overflow;
  wire test_fifo_tdata;
  wire [7:0] test_fifo_tdata;
  wire int1_out;
  wire int2_out;
  wire int3_out;
  wire int4_out;
  wire nCS;
  wire overrange1;
  wire overrange2;

  AXI_GPIO_Sim AXI_GPIO_Sim_i
       (.MISO(MISO),
        .MOSI(MOSI),
        .Rx_load_strobe(Rx_load_strobe),
        .SCLK(SCLK),
        .SPI_ck(SPI_ck),
        .SPI_data(SPI_data),
        .TX_Strobe(TX_Strobe),
        .Tx_load_strobe(Tx_load_strobe),
        .aclk(aclk),
        .aresetn(aresetn),
        .fifo1_count(fifo1_count),
        .fifo1_overflow(fifo1_overflow),
        .fifo2_count(fifo2_count),
        .fifo2_overflow(fifo2_overflow),
        .fifo3_count(fifo3_count),
        .fifo3_overflow(fifo3_overflow),
        .fifo4_count(fifo4_count),
        .fifo4_overflow(fifo4_overflow),
        .test_fifo_tvalid(test_fifo_tvalid),
        .test_fifo_tdata(test_fifo_tdata),
        .int1_out(int1_out),
        .int2_out(int2_out),
        .int3_out(int3_out),
        .int4_out(int4_out),
        .nCS(nCS),
        .overrange1(overrange1),
        .overrange2(overrange2));
endmodule
