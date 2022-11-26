//Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2021.2 (win64) Build 3367213 Tue Oct 19 02:48:09 MDT 2021
//Date        : Mon Feb 28 21:01:09 2022
//Host        : CCLDesktop running 64-bit major release  (build 9200)
//Command     : generate_target saturn_top_wrapper.bd
//Design      : saturn_top_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module saturn_top_wrapper
   (ADC1Ovr_In_N,
    ADC1Ovr_In_P,
    ADC1_ATTEN_CLK,
    ADC1_ATTEN_DAT,
    ADC1_ATTEN_LE,
    ADC1_CLKin_N,
    ADC1_CLKin_P,
    ADC1_In_N,
    ADC1_In_P,
    ADC2Ovr_In_N,
    ADC2Ovr_In_P,
    ADC2_ATTEN_CLK,
    ADC2_ATTEN_DAT,
    ADC2_ATTEN_LE,
    ADC2_CLKin_N,
    ADC2_CLKin_P,
    ADC2_In_N,
    ADC2_In_P,
    ADC_CLK,
    ADC_MISO,
    ADC_MOSI,
    ATU_TUNE,
    BCLK,
    BLINK_LED,
    BUFF_Alex_Pin1,
    BUFF_Alex_Pin8,
    BUF_Out_FPGA,
    CTRL_TRSW,
    DAC_Out_N,
    DAC_Out_P,
    DRIVER_PA_EN,
    Dac_Atten,
    Dac_Atten_Clk,
    Dac_Atten_Data,
    Dac_Atten_LE,
    Dac_Atten_Mode,
    EMC_CLK,
    FPGA_CM4_EN,
    GPIO_OUT,
    LEDOutputs,
    LRCLK,
    MCLK,
    MOX_strobe,
    PCIECLKREQN,
    PCI_LINK_LED,
    PCIe_T_SMBCLK,
    PCIe_T_SMBDAT,
    PROM_SPI_io0_io,
    PROM_SPI_io1_io,
    PROM_SPI_io2_io,
    PROM_SPI_io3_io,
    PROM_SPI_ss_io,
    RF_SPI_CK,
    RF_SPI_DATA,
    RF_SPI_RX_LOAD,
    RF_SPI_TX_LOAD,
    TXRX_RELAY,
    TX_DAC_PWM,
    TX_ENABLE,
    clock_122_in_n,
    clock_122_in_p,
    i2srxd,
    i2stxd,
    CODEC_SPI_CLK,
    CODEC_SPI_DATA,
    CODEC_CS,
    nADC_CS,
    pcie_7x_mgt_rtl_0_rxn,
    pcie_7x_mgt_rtl_0_rxp,
    pcie_7x_mgt_rtl_0_txn,
    pcie_7x_mgt_rtl_0_txp,
    pcie_diff_clock_rtl_clk_n,
    pcie_diff_clock_rtl_clk_p,
    pcie_reset_n,
    pll_cr,
    ref_in_10,
    status_in);
  input ADC1Ovr_In_N;
  input ADC1Ovr_In_P;
  output ADC1_ATTEN_CLK;
  output ADC1_ATTEN_DAT;
  output ADC1_ATTEN_LE;
  input ADC1_CLKin_N;
  input ADC1_CLKin_P;
  input [15:0]ADC1_In_N;
  input [15:0]ADC1_In_P;
  input ADC2Ovr_In_N;
  input ADC2Ovr_In_P;
  output ADC2_ATTEN_CLK;
  output ADC2_ATTEN_DAT;
  output ADC2_ATTEN_LE;
  input ADC2_CLKin_N;
  input ADC2_CLKin_P;
  input [15:0]ADC2_In_N;
  input [15:0]ADC2_In_P;
  output [0:0]ADC_CLK;
  input ADC_MISO;
  output [0:0]ADC_MOSI;
  output [0:0]ATU_TUNE;
  output BCLK;
  output [0:0]BLINK_LED;
  input BUFF_Alex_Pin1;
  input BUFF_Alex_Pin8;
  output [0:0]BUF_Out_FPGA;
  output CTRL_TRSW;
  output [15:0]DAC_Out_N;
  output [15:0]DAC_Out_P;
  output DRIVER_PA_EN;
  output [5:0]Dac_Atten;
  output [0:0]Dac_Atten_Clk;
  output [0:0]Dac_Atten_Data;
  output [0:0]Dac_Atten_LE;
  output [0:0]Dac_Atten_Mode;
  input EMC_CLK;
  output [0:0]FPGA_CM4_EN;
  output [23:0]GPIO_OUT;
  output [15:0]LEDOutputs;
  output LRCLK;
  output MCLK;
  output MOX_strobe;
  output [0:0]PCIECLKREQN;
  output [0:0]PCI_LINK_LED;
  input PCIe_T_SMBCLK;
  input PCIe_T_SMBDAT;
  inout PROM_SPI_io0_io;
  inout PROM_SPI_io1_io;
  inout PROM_SPI_io2_io;
  inout PROM_SPI_io3_io;
  inout [0:0]PROM_SPI_ss_io;
  output RF_SPI_CK;
  output RF_SPI_DATA;
  output RF_SPI_RX_LOAD;
  output RF_SPI_TX_LOAD;
  output [0:0]TXRX_RELAY;
  output TX_DAC_PWM;
  input TX_ENABLE;
  input clock_122_in_n;
  input clock_122_in_p;
  input i2srxd;
  output i2stxd;
  inout CODEC_SPI_CLK;
  inout CODEC_SPI_DATA;
  output CODEC_CS;
  output [0:0]nADC_CS;
  input [3:0]pcie_7x_mgt_rtl_0_rxn;
  input [3:0]pcie_7x_mgt_rtl_0_rxp;
  output [3:0]pcie_7x_mgt_rtl_0_txn;
  output [3:0]pcie_7x_mgt_rtl_0_txp;
  input [0:0]pcie_diff_clock_rtl_clk_n;
  input [0:0]pcie_diff_clock_rtl_clk_p;
  input pcie_reset_n;
  output pll_cr;
  input ref_in_10;
  input [9:0]status_in;

  wire ADC1Ovr_In_N;
  wire ADC1Ovr_In_P;
  wire ADC1_ATTEN_CLK;
  wire ADC1_ATTEN_DAT;
  wire ADC1_ATTEN_LE;
  wire ADC1_CLKin_N;
  wire ADC1_CLKin_P;
  wire [15:0]ADC1_In_N;
  wire [15:0]ADC1_In_P;
  wire ADC2Ovr_In_N;
  wire ADC2Ovr_In_P;
  wire ADC2_ATTEN_CLK;
  wire ADC2_ATTEN_DAT;
  wire ADC2_ATTEN_LE;
  wire ADC2_CLKin_N;
  wire ADC2_CLKin_P;
  wire [15:0]ADC2_In_N;
  wire [15:0]ADC2_In_P;
  wire [0:0]ADC_CLK;
  wire ADC_MISO;
  wire [0:0]ADC_MOSI;
  wire [0:0]ATU_TUNE;
  wire BCLK;
  wire [0:0]BLINK_LED;
  wire BUFF_Alex_Pin1;
  wire BUFF_Alex_Pin8;
  wire [0:0]BUF_Out_FPGA;
  wire CTRL_TRSW;
  wire [15:0]DAC_Out_N;
  wire [15:0]DAC_Out_P;
  wire DRIVER_PA_EN;
  wire [5:0]Dac_Atten;
  wire [0:0]Dac_Atten_Clk;
  wire [0:0]Dac_Atten_Data;
  wire [0:0]Dac_Atten_LE;
  wire [0:0]Dac_Atten_Mode;
  wire EMC_CLK;
  wire [0:0]FPGA_CM4_EN;
  wire [23:0]GPIO_OUT;
  wire [15:0]LEDOutputs;
  wire LRCLK;
  wire MCLK;
  wire MOX_strobe;
  wire [0:0]PCIECLKREQN;
  wire [0:0]PCI_LINK_LED;
  wire PCIe_T_SMBCLK;
  wire PCIe_T_SMBDAT;
  wire PROM_SPI_io0_i;
  wire PROM_SPI_io0_io;
  wire PROM_SPI_io0_o;
  wire PROM_SPI_io0_t;
  wire PROM_SPI_io1_i;
  wire PROM_SPI_io1_io;
  wire PROM_SPI_io1_o;
  wire PROM_SPI_io1_t;
  wire PROM_SPI_io2_i;
  wire PROM_SPI_io2_io;
  wire PROM_SPI_io2_o;
  wire PROM_SPI_io2_t;
  wire PROM_SPI_io3_i;
  wire PROM_SPI_io3_io;
  wire PROM_SPI_io3_o;
  wire PROM_SPI_io3_t;
  wire [0:0]PROM_SPI_ss_i_0;
  wire [0:0]PROM_SPI_ss_io_0;
  wire [0:0]PROM_SPI_ss_o_0;
  wire PROM_SPI_ss_t;
  wire RF_SPI_CK;
  wire RF_SPI_DATA;
  wire RF_SPI_RX_LOAD;
  wire RF_SPI_TX_LOAD;
  wire [0:0]TXRX_RELAY;
  wire TX_DAC_PWM;
  wire TX_ENABLE;
  wire clock_122_in_n;
  wire clock_122_in_p;
  wire i2srxd;
  wire i2stxd;
  wire [0:0]nADC_CS;
  wire [3:0]pcie_7x_mgt_rtl_0_rxn;
  wire [3:0]pcie_7x_mgt_rtl_0_rxp;
  wire [3:0]pcie_7x_mgt_rtl_0_txn;
  wire [3:0]pcie_7x_mgt_rtl_0_txp;
  wire [0:0]pcie_diff_clock_rtl_clk_n;
  wire [0:0]pcie_diff_clock_rtl_clk_p;
  wire pcie_reset_n;
  wire pll_cr;
  wire ref_in_10;
  wire [9:0]status_in;


  IOBUF PROM_SPI_io0_iobuf
       (.I(PROM_SPI_io0_o),
        .IO(PROM_SPI_io0_io),
        .O(PROM_SPI_io0_i),
        .T(PROM_SPI_io0_t));
  IOBUF PROM_SPI_io1_iobuf
       (.I(PROM_SPI_io1_o),
        .IO(PROM_SPI_io1_io),
        .O(PROM_SPI_io1_i),
        .T(PROM_SPI_io1_t));
  IOBUF PROM_SPI_io2_iobuf
       (.I(PROM_SPI_io2_o),
        .IO(PROM_SPI_io2_io),
        .O(PROM_SPI_io2_i),
        .T(PROM_SPI_io2_t));
  IOBUF PROM_SPI_io3_iobuf
       (.I(PROM_SPI_io3_o),
        .IO(PROM_SPI_io3_io),
        .O(PROM_SPI_io3_i),
        .T(PROM_SPI_io3_t));
  IOBUF PROM_SPI_ss_iobuf_0
       (.I(PROM_SPI_ss_o_0),
        .IO(PROM_SPI_ss_io[0]),
        .O(PROM_SPI_ss_i_0),
        .T(PROM_SPI_ss_t));

  saturn_top saturn_top_i
       (.ADC1Ovr_In_N(ADC1Ovr_In_N),
        .ADC1Ovr_In_P(ADC1Ovr_In_P),
        .ADC1_ATTEN_CLK(ADC1_ATTEN_CLK),
        .ADC1_ATTEN_DAT(ADC1_ATTEN_DAT),
        .ADC1_ATTEN_LE(ADC1_ATTEN_LE),
        .ADC1_CLKin_N(ADC1_CLKin_N),
        .ADC1_CLKin_P(ADC1_CLKin_P),
        .ADC1_In_N(ADC1_In_N),
        .ADC1_In_P(ADC1_In_P),
        .ADC2Ovr_In_N(ADC2Ovr_In_N),
        .ADC2Ovr_In_P(ADC2Ovr_In_P),
        .ADC2_ATTEN_CLK(ADC2_ATTEN_CLK),
        .ADC2_ATTEN_DAT(ADC2_ATTEN_DAT),
        .ADC2_ATTEN_LE(ADC2_ATTEN_LE),
        .ADC2_CLKin_N(ADC2_CLKin_N),
        .ADC2_CLKin_P(ADC2_CLKin_P),
        .ADC2_In_N(ADC2_In_N),
        .ADC2_In_P(ADC2_In_P),
        .ADC_CLK(ADC_CLK),
        .ADC_MISO(ADC_MISO),
        .ADC_MOSI(ADC_MOSI),
        .ATU_TUNE(ATU_TUNE),
        .BCLK(BCLK),
        .BLINK_LED(BLINK_LED),
        .BUFF_Alex_Pin1(BUFF_Alex_Pin1),
        .BUFF_Alex_Pin8(BUFF_Alex_Pin8),
        .BUF_Out_FPGA(BUF_Out_FPGA),
        .CTRL_TRSW(CTRL_TRSW),
        .DAC_Out_N(DAC_Out_N),
        .DAC_Out_P(DAC_Out_P),
        .DRIVER_PA_EN(DRIVER_PA_EN),
        .Dac_Atten(Dac_Atten),
        .Dac_Atten_Clk(Dac_Atten_Clk),
        .Dac_Atten_Data(Dac_Atten_Data),
        .Dac_Atten_LE(Dac_Atten_LE),
        .Dac_Atten_Mode(Dac_Atten_Mode),
        .EMC_CLK(EMC_CLK),
        .FPGA_CM4_EN(FPGA_CM4_EN),
        .GPIO_OUT(GPIO_OUT),
        .LEDOutputs(LEDOutputs),
        .LRCLK(LRCLK),
        .MCLK(MCLK),
        .MOX_strobe(MOX_strobe),
        .PCIECLKREQN(PCIECLKREQN),
        .PCI_LINK_LED(PCI_LINK_LED),
        .PCIe_T_SMBCLK(PCIe_T_SMBCLK),
        .PCIe_T_SMBDAT(PCIe_T_SMBDAT),
        .PROM_SPI_io0_i(PROM_SPI_io0_i),
        .PROM_SPI_io0_o(PROM_SPI_io0_o),
        .PROM_SPI_io0_t(PROM_SPI_io0_t),
        .PROM_SPI_io1_i(PROM_SPI_io1_i),
        .PROM_SPI_io1_o(PROM_SPI_io1_o),
        .PROM_SPI_io1_t(PROM_SPI_io1_t),
        .PROM_SPI_io2_i(PROM_SPI_io2_i),
        .PROM_SPI_io2_o(PROM_SPI_io2_o),
        .PROM_SPI_io2_t(PROM_SPI_io2_t),
        .PROM_SPI_io3_i(PROM_SPI_io3_i),
        .PROM_SPI_io3_o(PROM_SPI_io3_o),
        .PROM_SPI_io3_t(PROM_SPI_io3_t),
        .PROM_SPI_ss_i(PROM_SPI_ss_i_0),
        .PROM_SPI_ss_o(PROM_SPI_ss_o_0),
        .PROM_SPI_ss_t(PROM_SPI_ss_t),
        .RF_SPI_CK(RF_SPI_CK),
        .RF_SPI_DATA(RF_SPI_DATA),
        .RF_SPI_RX_LOAD(RF_SPI_RX_LOAD),
        .RF_SPI_TX_LOAD(RF_SPI_TX_LOAD),
        .TXRX_RELAY(TXRX_RELAY),
        .TX_DAC_PWM(TX_DAC_PWM),
        .TX_ENABLE(TX_ENABLE),
        .clock_122_in_n(clock_122_in_n),
        .clock_122_in_p(clock_122_in_p),
        .i2srxd(i2srxd),
        .i2stxd(i2stxd),
        .CODEC_SPI_CLK(CODEC_SPI_CLK),
        .CODEC_SPI_DATA(CODEC_SPI_DATA),
        .CODEC_CS(CODEC_CS),
        .nADC_CS(nADC_CS),
        .pcie_7x_mgt_rtl_0_rxn(pcie_7x_mgt_rtl_0_rxn),
        .pcie_7x_mgt_rtl_0_rxp(pcie_7x_mgt_rtl_0_rxp),
        .pcie_7x_mgt_rtl_0_txn(pcie_7x_mgt_rtl_0_txn),
        .pcie_7x_mgt_rtl_0_txp(pcie_7x_mgt_rtl_0_txp),
        .pcie_diff_clock_rtl_clk_n(pcie_diff_clock_rtl_clk_n),
        .pcie_diff_clock_rtl_clk_p(pcie_diff_clock_rtl_clk_p),
        .pcie_reset_n(pcie_reset_n),
        .pll_cr(pll_cr),
        .ref_in_10(ref_in_10),
        .status_in(status_in));
endmodule
