#!/bin/bash
#
# check that copies of design modules held inside the IP development projects under FPGA/IP
# are identical to the master copies in FPGA/sources/verilogmodules (or verilogmodules/unused).
# (IP/testbenches holds historical experiment snapshots and is not checked)
# a diverged copy is dangerous: regenerating that IP would silently use old code.
# exits 1 if any copy differs.
#
cd "$(dirname "$0")/../.." || exit 1          # FPGA folder
status=0; checked=0
while IFS= read -r copy; do
    name=$(basename "$copy")
    master=""
    [[ -f sources/verilogmodules/$name ]] && master=sources/verilogmodules/$name
    [[ -z "$master" && -f sources/verilogmodules/unused/$name ]] && master=sources/verilogmodules/unused/$name
    [[ -z "$master" ]] && continue
    checked=$((checked+1))
    if ! cmp -s "$master" "$copy"; then
        echo "DIFFERS: $copy  (master $master)"; status=1
    fi
done < <(find IP -name '*.v' -not -path 'IP/testbenches/*' -not -path '*/sim/*' -not -path '*/hdl/*' -not -name '*_tb.v' -not -name 'DDC_Block*')
echo "checked $checked IP copies"
[[ $status -eq 0 ]] && echo "all IP copies match their master"
exit $status
