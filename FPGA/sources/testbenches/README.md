# Saturn FPGA unit tests

Self checking unit tests for the hand written Verilog modules in `../verilogmodules`.
They run with Icarus Verilog (no Vivado needed); the older Vivado testbenches in this
folder (`RX_DDC_tb.v`, `TX_DUC_tb.v`, `IQModtb.sv`) are unchanged and still need Vivado IP.

| Path | Contents |
|---|---|
| `common/axil_master_bfm.v` | AXI4-Lite master model with handshake timeouts and RREADY/BREADY back-pressure |
| `common/axil_checker.v` | passive AXI4-Lite slave protocol checker |
| `common/axis_checker.v` | passive AXI-Stream protocol checker and beat counter |
| `common/axil_tb_bus.vh` | bus + BFM + checker in one include; `AXIL_SLAVE_PORTS` macro |
| `common/tb_helpers.vh` | `check_eq`, `check_true`, `finish_test` |
| `unit/tb_*.v` | one test per module; first `// SOURCES:` line lists the design files |
| `run_all.sh` | compiles and runs every test; a test passes if it prints `TEST PASS` |
| `check_ip_copies.sh` | fails if a module copy inside `FPGA/IP/` differs from its master in `verilogmodules/` |
| `prerelease_check.sh` | runs tests, IP copy check and lint; run before building a release |
| `lint.sh` | Verilator `-Wall` lint of every module, compared with `lint_baseline.txt` |

```
./prerelease_check.sh     # everything, before a release build
./run_all.sh              # all tests
./run_all.sh ddcmux       # tests whose name contains "ddcmux"
./lint.sh                 # fails if any module has more lint warnings than the baseline
./lint.sh --update        # accept the current warning counts as the new baseline
./check_ip_copies.sh      # IP project copies identical to verilogmodules/
```

Requirements: Icarus Verilog 12+ (`iverilog`, `vvp`), Verilator 5 (lint only).
