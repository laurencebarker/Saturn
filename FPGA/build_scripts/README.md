# Command line build scripts (Vivado 2023.1)

Batch mode alternative to the GUI build procedure in `FPGA/README.md`.

| Script | Does |
|---|---|
| `build_saturn.tcl` | Full build: refresh module references, validate every block design, create the HDL wrapper, synthesis, implementation, bitstream, timing/utilisation/DRC reports and the primary PROM `.bin` (SPIx1, s25fl256s, address 0, as described in `FPGA/documentation/Generating Configuration PROM file.docx`). |
| `replace_try.tcl` | Timing closure fallback: re-place and re-route an `opt_design` checkpoint with several placer directives, stop at the first that meets timing, write bitstream and `.bin`. |
| `build_stage2.tcl` | Same flow from the HDL wrapper onwards, without opening block designs. Use it after a `build_saturn.tcl` run that already refreshed and saved the block designs. |

```
vivado -mode batch -nojournal -log build.log -source build_saturn.tcl \
       -tclargs <path>/saturn_project.xpr <jobs> <out_dir>
```

`<jobs>` is the number of parallel runs; 2 is enough for 8 GB of RAM (peak is about 8 GB with swap).
Output in `<out_dir>`: `saturn_top_wrapper.bit`, `saturnprimary_candidate.bin/.prm`, `timing_summary.txt`,
`utilization.txt`, `drc.txt`, `ip_status.txt`.

## Notes

- `saturn_top_wrapper.v` is a generated file that is not in git. The scripts create it with `make_wrapper`
  and set it as top; without it Vivado picks an arbitrary module as top and placement fails.
- `update_module_reference` refreshes **all** module references, so the saved `.bd` files change a lot
  (dropped FREQ_HZ/CLK_DOMAIN user parameters, re-propagated by validation). Harmless for a build, but
  don't commit those files unless you intend to.
- Vivado 2023.1 is not supported on Debian 13. It works with these user-space workarounds (no root):
  - `libtinfo5`/`libncurses5` extracted from the Debian 12 packages, added to `LD_LIBRARY_PATH`
  - `en_US.UTF-8` locale (Vivado forces it) compiled with `localedef` into a user folder, `LOCPATH` set
  - on this system Vivado segfaulted after closing block designs in the same session; running
    `build_saturn.tcl` until it fails there and then `build_stage2.tcl` in a new session works around it.
