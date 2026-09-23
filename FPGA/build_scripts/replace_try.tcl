# re-place and re-route from the post opt_design checkpoint with several placer directives,
# stop at the first one that meets timing, then write bitstream + PROM image
# usage: vivado -mode batch -source replace_try.tcl -tclargs <opt.dcp> <out_dir>
set dcp [lindex $argv 0]
set out [lindex $argv 1]
file mkdir $out
foreach dir {ExtraNetDelay_high ExtraTimingOpt AltSpreadLogic_high SSI_SpreadLogic_high} {
    puts "INFO: trying place_design -directive $dir"
    open_checkpoint $dcp
    if {[catch {place_design -directive $dir} msg]} { puts "INFO: $dir not usable: $msg"; close_design; continue }
    phys_opt_design -directive AggressiveExplore
    route_design -directive AggressiveExplore
    phys_opt_design -directive AggressiveExplore
    set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
    set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
    set unrouted [llength [get_nets -quiet -hier -filter {ROUTE_STATUS == UNROUTED}]]
    puts "INFO: $dir -> WNS $wns WHS $whs"
    if {$wns >= 0 && $whs >= 0} {
        report_timing_summary -file $out/timing_summary.txt
        report_utilization -file $out/utilization.txt
        report_drc -file $out/drc.txt
        report_route_status -file $out/route_status.txt
        write_checkpoint -force $out/saturn_top_wrapper_routed.dcp
        write_bitstream -force $out/saturn_top_wrapper.bit
        write_cfgmem -format bin -size 32 -interface SPIx1 -loadbit "up 0x00000000 $out/saturn_top_wrapper.bit" -force $out/saturnprimary_candidate.bin
        puts "INFO: timing met with $dir: $out"
        exit 0
    }
    report_timing_summary -file $out/timing_summary_$dir.txt
    close_design
}
puts "ERROR: no placer directive met timing"
exit 1
