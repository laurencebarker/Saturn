## timing assertions
create_clock -period 10.000 -name {pcie_diff_clock_rtl_clk_p[0]} -waveform {0.000 5.000} [get_ports {pcie_diff_clock_rtl_clk_p[0]}]
create_clock -period 8.000 -name VIRTUAL_clk_125mhz -waveform {0.000 4.000}
create_clock -period 8.138 -name EMC_CLK -waveform {0.000 4.069} [get_ports EMC_CLK]



##PCIe reset constraints
# asynchronous input so no time to meet
set_input_delay -clock pcie_diff_clock_rtl_clk_p[0] -min -add_delay 0.000 [get_ports pcie_reset_n]
set_input_delay -clock pcie_diff_clock_rtl_clk_p[0] -max -add_delay 0.000 [get_ports pcie_reset_n]

## ADC input constraints
# LTC2208 tpd=1.3ns min 2.8ns max; assumed trace delay 0.1 to 0.5ns (approx 3cm to 15cm)
# see formula Xilinx UG949 p158
# adjusted because FPGA clock is about 0.6ns after ADC clock
#
set_input_delay -clock [get_clocks clock_122_in_p] -min -add_delay 0.700 [get_ports {ADC1_In_N[*]}]
set_input_delay -clock [get_clocks clock_122_in_p] -max -add_delay 3.200 [get_ports {ADC1_In_N[*]}]
set_input_delay -clock [get_clocks clock_122_in_p] -min -add_delay 0.700 [get_ports {ADC1_In_P[*]}]
set_input_delay -clock [get_clocks clock_122_in_p] -max -add_delay 3.200 [get_ports {ADC1_In_P[*]}]
set_input_delay -clock [get_clocks clock_122_in_p] -min -add_delay 0.700 [get_ports {ADC2_In_N[*]}]
set_input_delay -clock [get_clocks clock_122_in_p] -max -add_delay 3.200 [get_ports {ADC2_In_N[*]}]
set_input_delay -clock [get_clocks clock_122_in_p] -min -add_delay 0.700 [get_ports {ADC2_In_P[*]}]
set_input_delay -clock [get_clocks clock_122_in_p] -max -add_delay 3.200 [get_ports {ADC2_In_P[*]}]
set_input_delay -clock [get_clocks clock_122_in_p] -min -add_delay 0.700 [get_ports ADC1Ovr_In_N]
set_input_delay -clock [get_clocks clock_122_in_p] -max -add_delay 3.200 [get_ports ADC1Ovr_In_N]
set_input_delay -clock [get_clocks clock_122_in_p] -min -add_delay 0.700 [get_ports ADC1Ovr_In_P]
set_input_delay -clock [get_clocks clock_122_in_p] -max -add_delay 3.200 [get_ports ADC1Ovr_In_P]
set_input_delay -clock [get_clocks clock_122_in_p] -min -add_delay 0.700 [get_ports ADC2Ovr_In_N]
set_input_delay -clock [get_clocks clock_122_in_p] -max -add_delay 3.200 [get_ports ADC2Ovr_In_N]
set_input_delay -clock [get_clocks clock_122_in_p] -min -add_delay 0.700 [get_ports ADC2Ovr_In_P]
set_input_delay -clock [get_clocks clock_122_in_p] -max -add_delay 3.200 [get_ports ADC2Ovr_In_P]
## DAC output constraints
# MAX5891 tsu -1.5ns min; th 2.6ns min assumed trace delay 0.1 to 0.5ns (approx 3cm to 15cm)
## (this means data can change up to 1.5ns AFTER the clock edge)
# for formula see Xilinx UG949 p160
set_output_delay -clock [get_clocks clock_122_in_p] -min -add_delay -2.500 [get_ports {DAC_Out_N[*]}]
set_output_delay -clock [get_clocks clock_122_in_p] -max -add_delay -1.000 [get_ports {DAC_Out_N[*]}]
set_output_delay -clock [get_clocks clock_122_in_p] -min -add_delay -2.500 [get_ports {DAC_Out_P[*]}]
set_output_delay -clock [get_clocks clock_122_in_p] -max -add_delay -1.000 [get_ports {DAC_Out_P[*]}]


## RF SPI control outputs (Alex interface)
# timing should be guaranteed by design with edges separated by 12MHz clock cycles
create_clock -period 81.380 -name VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0 -waveform {0.000 40.690}
set_false_path -to [get_ports RF_SPI_CK]
set_false_path -to [get_ports RF_SPI_DATA]
set_false_path -to [get_ports RF_SPI_RX_LOAD]
set_false_path -to [get_ports RF_SPI_TX_LOAD]
#set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -min -add_delay 0.000 [get_ports RF_SPI_CK]
#set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -max -add_delay 0.000 [get_ports RF_SPI_CK]
#set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -min -add_delay 0.000 [get_ports RF_SPI_DATA]
#set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -max -add_delay 0.000 [get_ports RF_SPI_DATA]
#set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -min -add_delay 0.000 [get_ports RF_SPI_RX_LOAD]
#set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -max -add_delay 0.000 [get_ports RF_SPI_RX_LOAD]
#set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -min -add_delay 0.000 [get_ports RF_SPI_TX_LOAD]
#set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -max -add_delay 0.000 [get_ports RF_SPI_TX_LOAD]

## CODEC input & output constraints
# timing should be guaranteed by design with clock edges for data separated from BCLK
set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -min -add_delay 0.000 [get_ports BCLK]
set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -max -add_delay 0.000 [get_ports BCLK]
set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -min -add_delay 0.000 [get_ports LRCLK]
set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -max -add_delay 0.000 [get_ports LRCLK]
set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -min -add_delay 0.000 [get_ports i2stxd]
set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -max -add_delay 0.000 [get_ports i2stxd]
set_input_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -min -add_delay 0.000 [get_ports i2srxd]
set_input_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -max -add_delay 0.000 [get_ports i2srxd]

## serial atten control outputs
# timing should be guaranteed by design with clock edges for data separated by 12MHz clock cycles
set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -min -add_delay 0.000 [get_ports ADC1_ATTEN_CLK]
set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -max -add_delay 0.000 [get_ports ADC1_ATTEN_CLK]
set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -min -add_delay 0.000 [get_ports ADC1_ATTEN_DAT]
set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -max -add_delay 0.000 [get_ports ADC1_ATTEN_DAT]
set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -min -add_delay 0.000 [get_ports ADC1_ATTEN_LE]
set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -max -add_delay 0.000 [get_ports ADC1_ATTEN_LE]
set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -min -add_delay 0.000 [get_ports ADC2_ATTEN_CLK]
set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -max -add_delay 0.000 [get_ports ADC2_ATTEN_CLK]
set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -min -add_delay 0.000 [get_ports ADC2_ATTEN_DAT]
set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -max -add_delay 0.000 [get_ports ADC2_ATTEN_DAT]
set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -min -add_delay 0.000 [get_ports ADC2_ATTEN_LE]
set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -max -add_delay 0.000 [get_ports ADC2_ATTEN_LE]

## PWM DAC output
# asynchronous, so needs no timings
set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -min -add_delay 0.000 [get_ports TX_DAC_PWM]
set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -max -add_delay 0.000 [get_ports TX_DAC_PWM]

#RF analogue inputs (fwd, rev power etc)
set_false_path -to [get_ports {nADC_CS[0]}]
set_false_path -to [get_ports {ADC_MOSI[0]}]
set_false_path -to [get_ports {ADC_CLK[0]}]
set_false_path -from [get_ports ADC_MISO]


## asynchronous input constraints
# these all go to input synchroniser
# see formula Xilinx UG949 p158
set_input_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -min -add_delay 0.000 [get_ports {status_in[*]}]
set_input_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -max -add_delay 0.000 [get_ports {status_in[*]}]
set_input_delay -clock [get_clocks clock_122_in_p] -min -add_delay 0.000 [get_ports {{status_in[8]} {status_in[9]}}]
set_input_delay -clock [get_clocks clock_122_in_p] -max -add_delay 0.000 [get_ports {{status_in[8]} {status_in[9]}}]

## DAC atten output constraints
# these are not registered and require no timing
set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -min -add_delay 0.000 [get_ports {Dac_Atten[*]}]
set_output_delay -clock [get_clocks VIRTUAL_clk_out2_saturn_top_clk_wiz_0_0] -max -add_delay 0.000 [get_ports {Dac_Atten[*]}]

## LED and GPIO output constraints
# these are not registered and require no timing
set_false_path -to [get_ports {BLINK_LED[0]}]
set_false_path -to [get_ports {PCI_LINK_LED[0]}]
set_false_path -to [get_ports {LEDOutputs[*]}]
#set_output_delay -clock [get_clocks clock_122_in_p] -min -add_delay 0.000 [get_ports {LEDOutputs[*]}]
#set_output_delay -clock [get_clocks clock_122_in_p] -max -add_delay 0.000 [get_ports {LEDOutputs[*]}]
set_output_delay -clock [get_clocks clock_122_in_p] -min -add_delay 0.000 [get_ports {GPIO_OUT[*]}]
set_output_delay -clock [get_clocks clock_122_in_p] -max -add_delay 0.000 [get_ports {GPIO_OUT[*]}]

## I2C output constraints
# the timing is guaranteed by design
#set_output_delay -clock [get_clocks VIRTUAL_clk_125mhz] -min -add_delay 0.000 [get_ports iic_rtl_0_scl_io]
#set_output_delay -clock [get_clocks VIRTUAL_clk_125mhz] -max -add_delay 0.000 [get_ports iic_rtl_0_scl_io]
#set_output_delay -clock [get_clocks VIRTUAL_clk_125mhz] -min -add_delay 0.000 [get_ports iic_rtl_0_sda_io]
#set_output_delay -clock [get_clocks VIRTUAL_clk_125mhz] -max -add_delay 0.000 [get_ports iic_rtl_0_sda_io]
#set_input_delay -clock [get_clocks VIRTUAL_clk_125mhz] -min -add_delay 0.000 [get_ports iic_rtl_0_scl_io]
#set_input_delay -clock [get_clocks VIRTUAL_clk_125mhz] -max -add_delay 0.000 [get_ports iic_rtl_0_scl_io]
#set_input_delay -clock [get_clocks VIRTUAL_clk_125mhz] -min -add_delay 0.000 [get_ports iic_rtl_0_sda_io]
#set_input_delay -clock [get_clocks VIRTUAL_clk_125mhz] -max -add_delay 0.000 [get_ports iic_rtl_0_sda_io]

## asynchronous strobe output constraints
# these are not registered and require no timing
set_output_delay -clock [get_clocks clock_122_in_p] -min -add_delay 0.000 [get_ports {ATU_TUNE[0]}]
set_output_delay -clock [get_clocks clock_122_in_p] -max -add_delay 0.000 [get_ports {ATU_TUNE[0]}]
set_output_delay -clock [get_clocks clock_122_in_p] -min -add_delay 0.000 [get_ports CTRL_TRSW]
set_output_delay -clock [get_clocks clock_122_in_p] -max -add_delay 0.000 [get_ports CTRL_TRSW]
set_output_delay -clock [get_clocks clock_122_in_p] -min -add_delay 0.000 [get_ports DRIVER_PA_EN]
set_output_delay -clock [get_clocks clock_122_in_p] -max -add_delay 0.000 [get_ports DRIVER_PA_EN]
set_output_delay -clock [get_clocks clock_122_in_p] -min -add_delay 0.000 [get_ports TXRX_RELAY]
set_output_delay -clock [get_clocks clock_122_in_p] -max -add_delay 0.000 [get_ports TXRX_RELAY]
set_output_delay -clock [get_clocks clock_122_in_p] -min -add_delay 0.000 [get_ports MOX_strobe]
set_output_delay -clock [get_clocks clock_122_in_p] -max -add_delay 0.000 [get_ports MOX_strobe]


# serial prom constraints: see Xilinx PG153 p89-90
# You must provide all the delay numbers
# CCLK delay is 0.5, 8 ns min/max for Artix7-2; refer Data sheet
# Consider the max delay for worst case analysis
# Following are the SPI device parameters
# Max Tco 0
# Min Tco 6.5ns
# Setup time requirement 1.5ns
# Hold time requirement 2ns
# Following are the board/trace delay numbers
# Assumption is 2" to 4"
### End of user provided delay numbers
# this is to ensure min routing delay from SCK generation to STARTUP input
# User should change this value based on the results
# having more delay on this net reduces the Fmax
set_max_delay -datapath_only -from [get_pins -hier *SCK_O_reg_reg/C] -to [get_pins -hier *USRCCLKO] 2.000
set_min_delay -from [get_pins -hier *SCK_O_reg_reg/C] -to [get_pins -hier *USRCCLKO] 0.100
# Following command creates a divide by 2 clock
# It also takes into account the delay added by STARTUP block to route the CCLK
create_generated_clock -name clk_sck -source [get_pins -hierarchical *axi_quad_spi_0/ext_spi_clk] -edges {3 5 7} -edge_shift {8.000 8.000 8.000} [get_pins -hierarchical *USRCCLKO]
# Data is captured into FPGA on the second rising edge of ext_spi_clk after the SCK falling edge
# Data is driven by the FPGA on every alternate rising_edge of ext_spi_clk
#set_input_delay -clock clk_sck -clock_fall -max 8.800 [get_ports PROM_SPI_MISO]
#set_input_delay -clock clk_sck -clock_fall -min 0.400 [get_ports PROM_SPI_MISO]

set_multicycle_path -setup -from clk_sck -to [get_clocks -of_objects [get_pins [list saturn_top_i/PCIe/axi_quad_spi_0/U0/NO_DUAL_QUAD_MODE.QSPI_NORMAL/QSPI_LEGACY_MD_GEN.QSPI_CORE_INTERFACE_I/FIFO_EXISTS.CLK_CROSS_I/ext_spi_clk saturn_top_i/PCIe/axi_quad_spi_0/U0/NO_DUAL_QUAD_MODE.QSPI_NORMAL/QSPI_LEGACY_MD_GEN.QSPI_CORE_INTERFACE_I/FIFO_EXISTS.RX_FIFO_EMPTY_SYNC_AXI_2_SPI_CDC/ext_spi_clk saturn_top_i/PCIe/axi_quad_spi_0/U0/NO_DUAL_QUAD_MODE.QSPI_NORMAL/QSPI_LEGACY_MD_GEN.QSPI_CORE_INTERFACE_I/FIFO_EXISTS.TX_FIFO_II/ext_spi_clk saturn_top_i/PCIe/axi_quad_spi_0/U0/NO_DUAL_QUAD_MODE.QSPI_NORMAL/QSPI_LEGACY_MD_GEN.QSPI_CORE_INTERFACE_I/RESET_SYNC_AXI_SPI_CLK_INST/ext_spi_clk saturn_top_i/PCIe/axi_quad_spi_0/U0/NO_DUAL_QUAD_MODE.QSPI_NORMAL/QSPI_LEGACY_MD_GEN.QSPI_CORE_INTERFACE_I/ext_spi_clk saturn_top_i/PCIe/axi_quad_spi_0/U0/NO_DUAL_QUAD_MODE.QSPI_NORMAL/ext_spi_clk saturn_top_i/PCIe/axi_quad_spi_0/U0/ext_spi_clk saturn_top_i/PCIe/axi_quad_spi_0/ext_spi_clk]]] 2
set_multicycle_path -hold -end -from clk_sck -to [get_clocks -of_objects [get_pins -hierarchical */ext_spi_clk]] 1
# Data is captured into SPI on the following rising edge of SCK
# Data is driven by the IP on alternate rising_edge of the ext_spi_clk
set_output_delay -clock clk_sck -max 1.700 [get_ports PROM_SPI_io0_io]
set_output_delay -clock clk_sck -min -2.200 [get_ports PROM_SPI_io0_io]
set_output_delay -clock clk_sck -max 1.700 [get_ports PROM_SPI_io1_io]
set_output_delay -clock clk_sck -min -2.200 [get_ports PROM_SPI_io1_io]
set_output_delay -clock clk_sck -max 1.700 [get_ports PROM_SPI_io2_io]
set_output_delay -clock clk_sck -min -2.200 [get_ports PROM_SPI_io2_io]
set_output_delay -clock clk_sck -max 1.700 [get_ports PROM_SPI_io3_io]
set_output_delay -clock clk_sck -min -2.200 [get_ports PROM_SPI_io3_io]
set_output_delay -clock clk_sck -max 1.700 [get_ports {PROM_SPI_ss_io[0]}]
set_output_delay -clock clk_sck -min -2.200 [get_ports {PROM_SPI_ss_io[0]}]
set_multicycle_path -setup -start -from [get_clocks -of_objects [get_pins [list saturn_top_i/PCIe/axi_quad_spi_0/U0/NO_DUAL_QUAD_MODE.QSPI_NORMAL/QSPI_LEGACY_MD_GEN.QSPI_CORE_INTERFACE_I/FIFO_EXISTS.CLK_CROSS_I/ext_spi_clk saturn_top_i/PCIe/axi_quad_spi_0/U0/NO_DUAL_QUAD_MODE.QSPI_NORMAL/QSPI_LEGACY_MD_GEN.QSPI_CORE_INTERFACE_I/FIFO_EXISTS.RX_FIFO_EMPTY_SYNC_AXI_2_SPI_CDC/ext_spi_clk saturn_top_i/PCIe/axi_quad_spi_0/U0/NO_DUAL_QUAD_MODE.QSPI_NORMAL/QSPI_LEGACY_MD_GEN.QSPI_CORE_INTERFACE_I/FIFO_EXISTS.TX_FIFO_II/ext_spi_clk saturn_top_i/PCIe/axi_quad_spi_0/U0/NO_DUAL_QUAD_MODE.QSPI_NORMAL/QSPI_LEGACY_MD_GEN.QSPI_CORE_INTERFACE_I/RESET_SYNC_AXI_SPI_CLK_INST/ext_spi_clk saturn_top_i/PCIe/axi_quad_spi_0/U0/NO_DUAL_QUAD_MODE.QSPI_NORMAL/QSPI_LEGACY_MD_GEN.QSPI_CORE_INTERFACE_I/ext_spi_clk saturn_top_i/PCIe/axi_quad_spi_0/U0/NO_DUAL_QUAD_MODE.QSPI_NORMAL/ext_spi_clk saturn_top_i/PCIe/axi_quad_spi_0/U0/ext_spi_clk saturn_top_i/PCIe/axi_quad_spi_0/ext_spi_clk]]] -to clk_sck 2
set_multicycle_path -hold -from [get_clocks -of_objects [get_pins -hierarchical */ext_spi_clk]] -to clk_sck 1



## timing exceptions
# asynchronous reset out from PCIe core into synchronising double D flip flop
set_false_path -from [get_pins saturn_top_i/PCIe/xdma_0/inst/saturn_top_xdma_0_0_pcie2_to_pcie3_wrapper_i/pcie2_ip_i/inst/inst/user_reset_out_reg/C] -to [get_pins {saturn_top_i/PCIe/Double_D_register_syncareset/inst/Intermediate_reg[0]/D}]
set_false_path -from [get_pins saturn_top_i/PCIe/xdma_0/inst/saturn_top_xdma_0_0_pcie2_to_pcie3_wrapper_i/pcie2_ip_i/inst/inst/user_reset_out_reg/C] -to [get_pins {saturn_top_i/PCIe/Double_D_register_syncareset1/inst/Intermediate_reg[0]/D}]
# asynchronous reset in to pcie express core (copied from xilinx example design)
set_false_path -from [get_ports pcie_reset_n]
# asynchronous TX enable input
set_false_path -from [get_ports TX_ENABLE]

# codec SPI is output only
set_false_path -to [get_ports CODEC_SPI_CLK]
set_false_path -to [get_ports CODEC_SPI_DATA]

##
## clock monitor paths
##
set_false_path -from [get_pins saturn_top_i/clock_generator/clk_wiz_0/inst/mmcm_adv_inst/CLKOUT0] -to [get_pins saturn_top_i/clock_monitor_0/inst/ck3_rega_reg/D]
set_false_path -from [get_ports EMC_CLK] -to [get_pins saturn_top_i/clock_monitor_0/inst/ck2_rega_reg/D]
set_false_path -from [get_pins saturn_top_i/clock_generator/clk_wiz_0/inst/mmcm_adv_inst/CLKOUT0] -to [get_pins saturn_top_i/clock_monitor_0/inst/ck0_rega_reg/D]

#
# pcb version number path
# these are wired constant inputs
#
set_false_path -from [get_ports {pcb_version_id[0]}]
set_false_path -from [get_ports {pcb_version_id[1]}]
set_false_path -from [get_ports {pcb_version_id[2]}]
set_false_path -from [get_ports {pcb_version_id[3]}]







