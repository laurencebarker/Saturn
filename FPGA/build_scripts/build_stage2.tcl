# Saturn FPGA batch build, stage 2 (Vivado 2023.1)
# run after stage 1 (build_saturn.tcl up to BD validation) has refreshed and saved the block designs.
# kept separate because Vivado 2023.1 on Debian 13 segfaults after closing block designs
# usage: vivado -mode batch -source build_stage2.tcl -tclargs <xpr> <jobs> <out_dir>

set xpr   [lindex $argv 0]
set jobs  [lindex $argv 1]
set out   [lindex $argv 2]
file mkdir $out

open_project $xpr
set_param general.maxThreads $jobs

# HDL wrapper for the top block design (generated file, not in git; README step 7)
set wrapper [make_wrapper -files [get_files saturn_top.bd] -top]
if {[llength [get_files -quiet $wrapper]] == 0} { add_files -norecurse $wrapper }
set_property top saturn_top_wrapper [current_fileset]
update_compile_order -fileset sources_1
puts "INFO: top = [get_property top [current_fileset]] ($wrapper)"

set synth [current_run -synthesis]
set impl  [current_run -implementation]
puts "INFO: runs $synth / $impl"
reset_run $synth
launch_runs $impl -to_step write_bitstream -jobs $jobs
wait_on_run $impl

if {[get_property PROGRESS [get_runs $impl]] != "100%"} {
    puts "ERROR: implementation did not complete: [get_property STATUS [get_runs $impl]]"
    exit 1
}
open_run $impl
report_timing_summary -file $out/timing_summary.txt
report_utilization -file $out/utilization.txt
report_drc -file $out/drc.txt
set bit [glob [get_property DIRECTORY [get_runs $impl]]/*.bit]
file copy -force $bit $out/
write_cfgmem -format bin -size 32 -interface SPIx1 -loadbit "up 0x00000000 $bit" -force $out/saturnprimary_candidate.bin
puts "INFO: build complete: $out"
exit 0
