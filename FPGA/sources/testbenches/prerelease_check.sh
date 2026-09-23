#!/bin/bash
#
# checks to run before building a release bitstream:
#   1. all unit tests pass (Icarus Verilog)
#   2. module copies inside FPGA/IP match verilogmodules/
#   3. no module has more Verilator lint warnings than the baseline
# exits non-zero if any check fails. Needs iverilog/vvp and verilator.
#
cd "$(dirname "$0")" || exit 1
status=0
echo "=== unit tests";      ./run_all.sh        || status=1
echo "=== IP copies";       ./check_ip_copies.sh || status=1
echo "=== lint";            ./lint.sh           || status=1
echo
if [[ $status -eq 0 ]]; then echo "PRE-RELEASE CHECKS PASSED"; else echo "PRE-RELEASE CHECKS FAILED"; fi
exit $status
