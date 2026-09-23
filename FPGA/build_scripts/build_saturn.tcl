# Saturn FPGA batch build (Vivado 2023.1)
# usage: vivado -mode batch -source build_saturn.tcl -tclargs <xpr> <jobs> <out_dir>
# 1. open project, refresh module references (RTL changed) and upgrade-check IP
# 2. synthesis + implementation + bitstream on the project's current runs
# 3. timing summary and primary PROM image (SPIx1, s25fl256s, loaded at 0), as in
#    FPGA/documentation/Generating Configuration PROM file.docx

set xpr   [lindex $argv 0]
set jobs  [lindex $argv 1]
set out   [lindex $argv 2]
file mkdir $out

open_project $xpr
set_param general.maxThreads $jobs

# refresh module references whose RTL source changed
set refs [get_ips -quiet -filter {IPDEF =~ "xilinx.com:module_ref:*"}]
puts "INFO: [llength $refs] module reference IPs"
if {[llength $refs] > 0} {
    if {[catch { update_module_reference $refs } msg]} {
        puts "ERROR: update_module_reference failed - stopping: $msg"
        exit 1
    }
}
report_ip_status -file $out/ip_status.txt

foreach bd [get_files -quiet *.bd] {
    open_bd_design $bd
    if {[catch {validate_bd_design} msg]} {
        puts "ERROR: validation of $bd failed - stopping before synthesis: $msg"
        exit 1
    }
    save_bd_design
    close_bd_design [current_bd_design]
}


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
