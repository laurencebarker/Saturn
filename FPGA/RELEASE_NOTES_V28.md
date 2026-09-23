# FPGA release V28

Changes from the September 2026 Verilog review, branches `fix/fpga-phase-1` … `fix/fpga-phase-6`.

## Status

| Step | Status |
|---|---|
| RTL unit tests (`FPGA/sources/testbenches/prerelease_check.sh`) | 21/21 pass (V27 RTL: 4/21, see matrix below) |
| Vivado 2023.1 build | Done on 2026-09-22 with `FPGA/build_scripts` (~3 h, 2 jobs); V28 needed a re-place (see below) |
| Timing | All constraints met: WNS +0.055 ns, WHS +0.049 ns, 0 failing endpoints |
| Utilisation | LUT 40.4 %, FF 32.7 %, BRAM 74.8 % |
| DRC | 0 errors; 9 warnings, 3 advisories (DSP pipelining, BRAM async control) |
| Primary image | published as `FPGA/saturnprimary2026V28.bin`, 9 730 652 bytes, SPIx1 at 0x0 (same size/format as V27), sha256 `ba29d671...69d758` |
| Firmware version constant | **28** (`xlconstant_swversion`), rebuilt 2026-09-22 |
| Hardware test | Done: confirmed working on an ANAN G2 Ultra by Apache Labs |

## Changelog (relative to V27)

No software change is required. Register-level differences are listed at the end.

### TX safety
- **CW key down limit of 60 s** (`cw_key_ramp`, parameter `KEYDOWN_TIMEOUT_MS`, 0 = off). If the paddle or the
  CWX bit stays down longer, the envelope ramps down and PTT is released until the key is released.
  Previously only the FIFO activity watchdog could stop TX, and only if the host stopped streaming.
- **Paddles, IO8 and ATU tune inputs no longer read as pressed at power-up** (`debounce`, ~14 ms after
  configuration before). New parameter `INITIAL_LEVEL` (default 1: inputs idle high).
- **Activity watchdog output is 0 (TX disabled) from power-up**, before the first reset.
- **PWM DAC 0 gives 0 % duty** (was 1/256); 255 still gives 100 %.

### TX data path
- **I/Q / envelope deinterleaver**: turning EER off after an odd number of samples sent every later I/Q
  sample to the envelope output. The output stage was rewritten; it always restarts on the I/Q output.
- **Sidetone arithmetic**: multiplier rounds and saturates ((-32768)*(-32768) no longer flips sign);
  adder saturates instead of wrapping.

### CW keyer (iambic)
- Dash length was wrong at high weight and low speed (counter sized for weight <= 66).
- Speed 0 (reset value) no longer divides by zero; treated as 1 WPM.
- **IO8 external key now keys in straight/bug mode**, not only in iambic mode.

### RX
- **DDC multiplexer** can always shut down, even if a DDC stops delivering samples (16384-clock timeout,
  shutdown only; normal operation unchanged).
- **Wideband capture**: words lost because the FIFO was not ready are flagged in **bit 31 of the control
  register readback (0xD000)**. Status register 0xD00C is unchanged (software uses its bits 29:0 as count).
  New `m_axis_tready` port (joins the existing interface connection automatically).

### Alex filter board
- Non-zero bits 31:16 in the TX word caused endless 16-bit TX shifting and starved RX updates (RX antenna
  and filters stopped changing). Only bits 15:0 are compared now.
- The shift of zeros at reset ran the SPI clock 12x too fast; the clock divider is now free running.

### Status registers
- **ADC/FIFO overflow reader (0x5000, 0x6000)**: events arriving during a read are no longer lost; reading
  the peak registers (0x4/0x8) no longer clears the overflow flags; peak of -32768 reads 0x00008000
  (was 0xFFFF8000; software happened to read it correctly because it stores 16 bits).
- **FIFO monitor (0x9000)**: no lost flags; threshold 0 means "no threshold".

### Bus and DMA
- **Stray writes no longer hang the AXI bus** (and probably the Raspberry Pi): codec SPI 0x14004/0x1400C
  (0x14008 also started an SPI shift), read-only blocks at 0x4000, 0x5000, 0x6000, 0xA000. They are now
  acknowledged and ignored.
- **Read data held stable until RREADY** in every hand written AXI-Lite slave (AXI protocol rule).
- **DMA stream writer**: one write response per burst, also when the master sends W data of the next burst
  early (a burst could previously never get its response and hang).
- Codec SPI busy bit (0x14008) also covers the clocks between the write and the start of the shift.

### Internal robustness (no visible effect expected)
- 2 flip-flop synchronisers on SPI MISO (power ADC, codec); clock monitor uses a proper 2-stage synchroniser.
- I2S receiver no longer drops a sample arriving in the same clock as a handshake.
- Blocking assignments in clocked logic replaced; missing resets and power-up values added.

### Repository
- 21 self checking unit tests, Verilator lint baseline, IP copy check, `prerelease_check.sh`.
- Unused modules moved to `verilogmodules/unused`, stale wrapper removed, `IP/` copies synced.
- Command line Vivado build scripts in `FPGA/build_scripts`.

## Automated test matrix (RTL simulation, Icarus Verilog)

Same test files run against the V27 RTL (`Saturn` tree, branch `fix/fpga-phase-1`) and the fixed RTL
(`Saturn-fixes`, branch `fix/fpga-phase-6`): `FPGA/sources/testbenches/run_all.sh`.

| Test | Module(s) | V27 RTL | Fixed RTL | What the V27 failure shows |
|---|---|---|---|---|
| tb_alex_spi | AXILite_Alex_SPI | FAIL | PASS | TX word with bits 31:16 set: 4+ TX frames per write, RX frames never sent; SPI clock too fast in reset |
| tb_axi_spi_adc | AXI_SPI_ADC | FAIL | PASS | nCS/SCLK/MOSI undefined in reset; stray write hangs the bus |
| tb_axil_config | AXIL_ConfigReg_256/64 | PASS | PASS | (regression test) |
| tb_axil_read64 | AXIL_ReadReg_64 | FAIL | PASS | write channel undriven: stray write hangs; RDATA changes during a read |
| tb_axil_spiwriter | AXIL_SPIWriter | FAIL | PASS | write to 0x4/0xC hangs the bus, every later write times out |
| tb_axis_adder | axis_adder | FAIL | PASS | 30000+10000 = -25536 (wraps) |
| tb_axis_deinterleaver | AXIS_Deinterleaver | FAIL | PASS | after EER off, I/Q samples come out of the envelope output |
| tb_axis_multiplier | axis_multiplier | FAIL | PASS | (-32768)*(-32768) = -32768; truncation bias |
| tb_clock_monitor | clock_monitor | FAIL | PASS | dout undefined after reset |
| tb_cw_key_ramp | cw_key_ramp | PASS | PASS | (regression test: delay, ramp, dwell, hang) |
| tb_cw_key_timeout | cw_key_ramp | FAIL (no parameter) | PASS | no key down limit exists |
| tb_ddcmux | AXIS_DDC_Multiplexer | FAIL | PASS | disable never completes if a DDC stops |
| tb_debounce_pwm | debounce, PWM_DAC | FAIL | PASS | idle key reads pressed at power-up; PWM 0 gives 4/1024 duty |
| tb_fifo_monitor | FIFO_Monitor | FAIL | PASS | threshold 0: permanent over-threshold, no underflow; lost overflow events |
| tb_fifo_overflow_reader | AXI_FIFO_overflow_reader | FAIL | PASS | events near a read lost; peak reads clear flags; peak 0xFFFF8000; stray write hangs |
| tb_i2s_loopback | i2s_clk_lrclk_gen, I2S_xmit, I2S_rcv | PASS | PASS | (regression test: codec audio loopback) |
| tb_iambic | iambic | FAIL | PASS | dash length wrong at weight 255; speed 0 undefined; IO8 ignored in straight mode |
| tb_ptt_atu_gate | PTTATUGate | PASS | PASS | (regression test: no PTT glitch during ATU tune) |
| tb_stream_reader_writer | AXI_Stream_Reader_Writer | FAIL | PASS | 20 of 40 bursts get a write response when W data is sent early |
| tb_watchdog | Watchdog | FAIL | PASS | TX enable undefined at power-up |
| tb_wideband_collect | Wideband_Collect | FAIL (no port) | PASS | no TREADY: lost words not detectable |
| **Total** | | **4 / 21** | **21 / 21** | |

## Hardware test plan and matrix

Use a dummy load and low drive for every TX test. Keep `saturnprimary2024V27.bin` at hand to go back with
`flashwriter` (the golden/fallback image is never touched). Program `saturnprimary_candidate.bin` as the
**primary** image, then power off and on.

`axi_rw` is the register read/write tool in `sw_tools/axi_rw` (runs on the Pi).
**Never do the "stray write" tests (H18) with V27 loaded**: they can hang the PCIe bus and the Pi.

Fill the last two columns with PASS/FAIL (N/T = not tested). A test marked "same" should behave identically
on both images; the others show the expected difference.

| # | Test | How | Expected V27 | Expected candidate | V27 | Candidate |
|---|---|---|---|---|---|---|
| H1 | Power-up | power on, watch relays/PTT LED; clock LED | no TX, LED blinks | same | | |
| H2 | Version | `FPGAVersion` on the Pi | 27 | 28 | | |
| H3 | Basic RX/TX | Thetis RX all bands, SSB TX | works | same | | |
| H4 | Long run | RX (and some TX) for >= 1 h, watch p2app console | no FIFO errors | same | | |
| H5 | RX rates | switch 48k..1536k, several receivers | works | same | | |
| H6 | RX start/stop | start/stop RX in Thetis 20 times | works | same (never locks up) | | |
| H7 | PureSignal | enable PS, calibrate | works | same | | |
| H8 | Wideband | wideband panadapter on | works | same | | |
| H9 | Alex switching | change bands and RX/TX antennas | relays switch | same | | |
| H10 | Alex bits 31:16 | `axi_rw`: read 0xB000, write value \| 0x00010000, then change RX antenna/band | RX filters/antenna freeze | RX filters/antenna still change | | |
| H11 | Iambic keyer | modes A/B, several speeds | works | same | | |
| H12 | High weight | max weight, low WPM, measure dash vs dot | dash too short/wrong at weight > 66 | dash = 3 x dot x weight/50 | | |
| H13 | IO8 key | straight key on IO8, keyer in straight mode, then iambic | keys only in iambic mode | keys in both modes | | |
| H14 | Sidetone | sidetone volume max, key fast | clean | same (the fix only matters at exact negative full scale) | | |
| H15 | CW 60 s limit | hold key down > 60 s (dummy load, low power) | TX stays on | RF ramps down and PTT drops at 60 s; works again after release | | |
| H16 | Host stop | transmit, then close Thetis / pull network | TX stops within ~2 s | same | | |
| H17 | Drive 0 | TX with drive level 0, watch power meter | ~0 (tiny PWM residual) | 0 | | |
| H18 | Stray writes | `axi_rw`: write any value to 0x4000, 0x5000, 0x6000, 0xA000, 0x14004, 0x1400C | **do not run** (bus hang) | each write returns at once, radio keeps working, reads unchanged | N/T | |
| H19 | ADC overload | attenuator 0 dB, strong signal | overload shown, peak level | same | | |
| H20 | Codec audio | mic in, speaker out | works | same | | |

The image built from these sources was tested by Apache Labs on an ANAN G2 Ultra and works correctly.
The version history entry is in `FPGA/README.md` and the image is published as `FPGA/saturnprimary2026V28.bin`.

## Vivado notes

- **Timing margin is small.** The first build (version 27 constant) met timing with WNS +0.145 ns. After
  changing only the version constant to 28, the project strategy (`Performance_ExplorePostRoutePhysOpt`)
  gave WNS -0.306 ns: 9 endpoints of the Xilinx XDMA PCIe core, `gt_rx_valid_filter[0]/gt_rxvalid_q_reg`
  at 250 MHz (`clk_250mhz_mux_x0y0`), 73 % routing delay, i.e. a placement effect, not the new RTL.
  Post-route `phys_opt_design`/`route_design -directive AggressiveExplore` only reached -0.300 ns.
  Re-placing from the `opt_design` checkpoint with `place_design -directive ExtraNetDelay_high`
  (`FPGA/build_scripts/replace_try.tcl`) met timing: WNS +0.055 ns. If a future build fails the same way,
  run that script on `saturn_top_wrapper_opt.dcp` instead of rebuilding.

- `FPGA/build_scripts/README.md`: command line build, Debian 13 workarounds.
- Module reference changes that need attention when opening the project in the GUI:
  - `Wideband_Collect_0/m_axis` has TREADY (verified: `HAS_TREADY = 1` after refresh, joins the existing
    interface connection to `byteswap_64_0`).
  - New parameters with safe defaults: `AXIS_DDC_Multiplexer.SHUTDOWN_TIMEOUT` (16384),
    `cw_key_ramp.KEYDOWN_TIMEOUT_MS` (60000), `debounce.INITIAL_LEVEL` (1).

## Register / behaviour changes visible to software

| Register | Change |
|---|---|
| Wideband control 0xD000 (read) | bit 31 = words lost in last record (read only). Status 0xD00C unchanged. |
| Codec SPI 0x14008 (busy) | also set between the write response and the start of the shift |
| FIFO monitor thresholds | threshold 0 = no threshold (software always sets the FIFO depth) |
| ADC overflow 0x5000 | reading 0x4/0x8 no longer clears overflow bits; 0x4/0x8 upper 16 bits always 0 |
| Read-only register blocks | writes acknowledged (OKAY) and ignored instead of hanging |
