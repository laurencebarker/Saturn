# Unused modules

These modules are not instantiated in any block design of the current Saturn project
(`saturn_top`, `DDC_Block`, `TX_DUC`, `audio_codec`, `IQ_Modulation_Select`, `RX_TBBLK`).
They were moved here so the active design sources are easier to review; they are kept
for reference and for the obsolete `create_saturn_project.tcl`.

| File | Module | Note |
|---|---|---|
| `ADC_overrange_latch_reader.v` | `ADC_overrange_reader` | same code as `AXI_ADC_overrange_latch_reader.v` |
| `AXI_ADC_overrange_latch_reader.v` | `AXI_ADC_overrange_reader` | replaced by `AXI_FIFO_overflow_reader` |
| `axi_cfg_register.v` | `axi_cfg_register` | replaced by `AXIL_ConfigReg_*` |
| `axi_stream_interleaver.v` | `AXIS_Interleaver` | |
| `axi_stream_resizer.v` | `AXIS_Sizer_48to64` | known to lose samples under output back-pressure |
| `cordic.v` | `axis_cordic` | TX CORDIC removed in V24 (DDS restored) |
| `overrange_latch.v` | `overrange_latch` | |
| `RF_SPI.v` | `SPI` | older Alex shifter, replaced by `AXILite_Alex_SPI` |
