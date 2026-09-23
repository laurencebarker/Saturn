#!/bin/bash
#
# Verilator lint of every design module in verilogmodules/
# writes one summary line per module (warning count) and compares with lint_baseline.txt
# usage: ./lint.sh            compare against baseline (fails if any module got worse)
#        ./lint.sh --update   rewrite the baseline
#
cd "$(dirname "$0")" || exit 1
MODDIR=../verilogmodules
OUT=$(mktemp)
for f in "$MODDIR"/*.v; do
    top=$(grep -a -m1 -oE '^\s*module\s+[A-Za-z_0-9]+' "$f" | awk '{print $2}')
    n=$(verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-MULTITOP -Wno-PROCASSINIT --top-module "$top" "$f" 2>&1 \
        | grep -cE '^%(Warning|Error)')
    printf "%-40s %s\n" "$(basename "$f")" "$n" >> "$OUT"
done
if [[ "$1" == "--update" ]]; then
    cp "$OUT" lint_baseline.txt; cat lint_baseline.txt; exit 0
fi
worse=0
while read -r file count; do
    base=$(awk -v f="$file" '$1==f {print $2}' lint_baseline.txt)
    if [[ -z "$base" ]]; then echo "NEW   $file $count"
    elif (( count > base )); then echo "WORSE $file $base -> $count"; worse=1
    elif (( count < base )); then echo "BETTER $file $base -> $count"
    fi
done < "$OUT"
[[ $worse -eq 0 ]] && echo "lint: no module worse than baseline"
exit $worse
