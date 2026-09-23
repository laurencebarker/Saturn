#!/bin/bash
#
# run all self checking unit tests in unit/ using Icarus Verilog
# each test file unit/tb_*.v declares the design files it needs in a line:
#     // SOURCES: axil_SPIWriter.v other.v
# (paths relative to FPGA/sources/verilogmodules)
# a test passes if its simulation output contains a line starting "TEST PASS"
#
# usage: ./run_all.sh [pattern]      eg ./run_all.sh spiwriter
#
cd "$(dirname "$0")" || exit 1
MODDIR=../verilogmodules
BUILD=${BUILD_DIR:-$(mktemp -d)}
PATTERN=${1:-}
TO=$(command -v timeout || command -v gtimeout)
[[ -n "$TO" ]] && TO="$TO 300"
pass=0; fail=0; failed=()

for tb in unit/tb_*.v; do
    name=$(basename "$tb" .v)
    [[ -n "$PATTERN" && "$name" != *"$PATTERN"* ]] && continue
    srcs=$(grep -m1 '// SOURCES:' "$tb" | sed 's#.*// SOURCES:##')
    files=()
    for s in $srcs; do files+=("$MODDIR/$s"); done
    if ! iverilog -g2012 -Wall -Wno-timescale -Wno-implicit-dimensions -Wno-portbind -Wno-sensitivity-entire-array \
            -I common -o "$BUILD/$name.vvp" -s "$name" common/*.v "${files[@]}" "$tb" > "$BUILD/$name.compile.log" 2>&1; then
        echo "FAIL  $name (compile)"; sed 's/^/      /' "$BUILD/$name.compile.log" | head -20
        fail=$((fail+1)); failed+=("$name"); continue
    fi
    (cd "$BUILD" && $TO vvp -n "$name.vvp" > "$name.log" 2>&1)
    if grep -q '^TEST PASS' "$BUILD/$name.log"; then
        echo "PASS  $name"; pass=$((pass+1))
    else
        echo "FAIL  $name"; grep -E 'ERROR|FAIL' "$BUILD/$name.log" | head -10 | sed 's/^/      /'
        fail=$((fail+1)); failed+=("$name")
    fi
done

echo "----"
echo "passed: $pass  failed: $fail"
[[ $fail -gt 0 ]] && echo "failed tests: ${failed[*]}" && echo "logs in $BUILD"
exit $(( fail > 0 ))
