
################################################################
# This is a generated script based on design: TX_DUC
#
# Though there are limitations about the generated script,
# the main purpose of this utility is to make learning
# IP Integrator Tcl commands easier.
################################################################

namespace eval _tcl {
proc get_script_folder {} {
   set script_path [file normalize [info script]]
   set script_folder [file dirname $script_path]
   return $script_folder
}
}
variable script_folder
set script_folder [_tcl::get_script_folder]

################################################################
# Check if script is running in correct Vivado version.
################################################################
set scripts_vivado_version 2023.1
set current_vivado_version [version -short]

if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
   puts ""
   catch {common::send_gid_msg -ssname BD::TCL -id 2041 -severity "ERROR" "This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Please run the script in Vivado <$scripts_vivado_version> then open the design in Vivado <$current_vivado_version>. Upgrade the design by running \"Tools => Report => Report IP Status...\", then run write_bd_tcl to create an updated script."}

   return 1
}

################################################################
# START
################################################################

# To test this script, run the following commands from Vivado Tcl console:
# source TX_DUC_script.tcl


# The design that will be created by this Tcl script contains the following 
# module references:
# D_register, axis_constant, axis_variable, axis_variable, cvt_offset_binary, regmux_2_1, LFSR_Random_Number_Generator

# Please add the sources of those modules before sourcing this Tcl script.

# If there is no project opened, this script will create a
# project, but make sure you do not have an existing project
# <./myproj/project_1.xpr> in the current working folder.

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
   create_project project_1 myproj -part xc7a200tfbg676-2
}


# CHANGE DESIGN NAME HERE
variable design_name
set design_name TX_DUC

# If you do not already have an existing IP Integrator design open,
# you can create a design using the following command:
#    create_bd_design $design_name

# Creating design if needed
set errMsg ""
set nRet 0

set cur_design [current_bd_design -quiet]
set list_cells [get_bd_cells -quiet]

if { ${design_name} eq "" } {
   # USE CASES:
   #    1) Design_name not set

   set errMsg "Please set the variable <design_name> to a non-empty value."
   set nRet 1

} elseif { ${cur_design} ne "" && ${list_cells} eq "" } {
   # USE CASES:
   #    2): Current design opened AND is empty AND names same.
   #    3): Current design opened AND is empty AND names diff; design_name NOT in project.
   #    4): Current design opened AND is empty AND names diff; design_name exists in project.

   if { $cur_design ne $design_name } {
      common::send_gid_msg -ssname BD::TCL -id 2001 -severity "INFO" "Changing value of <design_name> from <$design_name> to <$cur_design> since current design is empty."
      set design_name [get_property NAME $cur_design]
   }
   common::send_gid_msg -ssname BD::TCL -id 2002 -severity "INFO" "Constructing design in IPI design <$cur_design>..."

} elseif { ${cur_design} ne "" && $list_cells ne "" && $cur_design eq $design_name } {
   # USE CASES:
   #    5) Current design opened AND has components AND same names.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 1
} elseif { [get_files -quiet ${design_name}.bd] ne "" } {
   # USE CASES: 
   #    6) Current opened design, has components, but diff names, design_name exists in project.
   #    7) No opened design, design_name exists in project.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 2

} else {
   # USE CASES:
   #    8) No opened design, design_name not in project.
   #    9) Current opened design, has components, but diff names, design_name not in project.

   common::send_gid_msg -ssname BD::TCL -id 2003 -severity "INFO" "Currently there is no design <$design_name> in project, so creating one..."

   create_bd_design $design_name

   common::send_gid_msg -ssname BD::TCL -id 2004 -severity "INFO" "Making design <$design_name> as current_bd_design."
   current_bd_design $design_name

}

common::send_gid_msg -ssname BD::TCL -id 2005 -severity "INFO" "Currently the variable <design_name> is equal to \"$design_name\"."

if { $nRet != 0 } {
   catch {common::send_gid_msg -ssname BD::TCL -id 2006 -severity "ERROR" $errMsg}
   return $nRet
}

set bCheckIPsPassed 1
##################################################################
# CHECK IPs
##################################################################
set bCheckIPs 1
if { $bCheckIPs == 1 } {
   set list_check_ips "\ 
xilinx.com:ip:xlconstant:1.1\
xilinx.com:ip:xlslice:1.0\
xilinx.com:ip:axis_broadcaster:1.1\
xilinx.com:ip:axis_combiner:1.1\
xilinx.com:ip:axis_dwidth_converter:1.1\
xilinx.com:ip:cic_compiler:4.0\
xilinx.com:ip:cmpy:6.0\
xilinx.com:ip:dds_compiler:6.0\
xilinx.com:ip:fir_compiler:7.2\
xilinx.com:ip:mult_gen:12.0\
"

   set list_ips_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2011 -severity "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

   foreach ip_vlnv $list_check_ips {
      set ip_obj [get_ipdefs -all $ip_vlnv]
      if { $ip_obj eq "" } {
         lappend list_ips_missing $ip_vlnv
      }
   }

   if { $list_ips_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2012 -severity "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
      set bCheckIPsPassed 0
   }

}

##################################################################
# CHECK Modules
##################################################################
set bCheckModules 1
if { $bCheckModules == 1 } {
   set list_check_mods "\ 
D_register\
axis_constant\
axis_variable\
axis_variable\
cvt_offset_binary\
regmux_2_1\
LFSR_Random_Number_Generator\
"

   set list_mods_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2020 -severity "INFO" "Checking if the following modules exist in the project's sources: $list_check_mods ."

   foreach mod_vlnv $list_check_mods {
      if { [can_resolve_reference $mod_vlnv] == 0 } {
         lappend list_mods_missing $mod_vlnv
      }
   }

   if { $list_mods_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2021 -severity "ERROR" "The following module(s) are not found in the project: $list_mods_missing" }
      common::send_gid_msg -ssname BD::TCL -id 2022 -severity "INFO" "Please add source files for the missing module(s) above."
      set bCheckIPsPassed 0
   }
}

if { $bCheckIPsPassed != 1 } {
  common::send_gid_msg -ssname BD::TCL -id 2023 -severity "WARNING" "Will not continue with creation of design due to the error(s) above."
  return 3
}

##################################################################
# DESIGN PROCs
##################################################################



# Procedure to create entire design; Provide argument to make
# procedure reusable. If parentCell is "", will use root.
proc create_root_design { parentCell } {

  variable script_folder
  variable design_name

  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj


  # Create interface ports
  set S_AXIS [ create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:axis_rtl:1.0 S_AXIS ]
  set_property -dict [ list \
   CONFIG.FREQ_HZ {122880000} \
   CONFIG.HAS_TKEEP {0} \
   CONFIG.HAS_TLAST {0} \
   CONFIG.HAS_TREADY {1} \
   CONFIG.HAS_TSTRB {0} \
   CONFIG.LAYERED_METADATA {undef} \
   CONFIG.TDATA_NUM_BYTES {6} \
   CONFIG.TDEST_WIDTH {0} \
   CONFIG.TID_WIDTH {0} \
   CONFIG.TUSER_WIDTH {0} \
   ] $S_AXIS


  # Create ports
  set TXConfig [ create_bd_port -dir I -from 31 -to 0 TXConfig ]
  set TXDACData [ create_bd_port -dir O -from 15 -to 0 TXDACData ]
  set TXLOTune [ create_bd_port -dir I -from 31 -to 0 TXLOTune ]
  set TXSamplesToRX [ create_bd_port -dir O -from 15 -to 0 TXSamplesToRX ]
  set cic_rate [ create_bd_port -dir I -from 15 -to 0 cic_rate ]
  set clk122 [ create_bd_port -dir I -type clk -freq_hz 122880000 clk122 ]
  set_property -dict [ list \
   CONFIG.ASSOCIATED_RESET {resetn1} \
 ] $clk122
  set resetn1 [ create_bd_port -dir I -type rst resetn1 ]
  set sel [ create_bd_port -dir I sel ]

  # Create instance: xlconstant_16x0, and set properties
  set xlconstant_16x0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 xlconstant_16x0 ]
  set_property -dict [list \
    CONFIG.CONST_VAL {0} \
    CONFIG.CONST_WIDTH {16} \
  ] $xlconstant_16x0


  # Create instance: xlslice_2, and set properties
  set xlslice_2 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 xlslice_2 ]
  set_property -dict [list \
    CONFIG.DIN_FROM {19} \
    CONFIG.DIN_TO {0} \
    CONFIG.DIN_WIDTH {48} \
    CONFIG.DOUT_WIDTH {20} \
  ] $xlslice_2


  # Create instance: xlslice_3, and set properties
  set xlslice_3 [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:1.0 xlslice_3 ]
  set_property -dict [list \
    CONFIG.DIN_FROM {21} \
    CONFIG.DIN_TO {4} \
    CONFIG.DOUT_WIDTH {18} \
  ] $xlslice_3


  # Create instance: D_register_2, and set properties
  set block_name D_register
  set block_cell_name D_register_2
  if { [catch {set D_register_2 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $D_register_2 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
    set_property CONFIG.DATA_WIDTH {16} $D_register_2


  # Create instance: axis_constant_0, and set properties
  set block_name axis_constant
  set block_cell_name axis_constant_0
  if { [catch {set axis_constant_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $axis_constant_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: axis_variable_0, and set properties
  set block_name axis_variable
  set block_cell_name axis_variable_0
  if { [catch {set axis_variable_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $axis_variable_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
    set_property CONFIG.AXIS_TDATA_WIDTH {16} $axis_variable_0


  # Create instance: axis_variable_1, and set properties
  set block_name axis_variable
  set block_cell_name axis_variable_1
  if { [catch {set axis_variable_1 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $axis_variable_1 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
    set_property CONFIG.AXIS_TDATA_WIDTH {16} $axis_variable_1


  # Create instance: cvt_offset_binary_0, and set properties
  set block_name cvt_offset_binary
  set block_cell_name cvt_offset_binary_0
  if { [catch {set cvt_offset_binary_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $cvt_offset_binary_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create instance: regmux_2_1_0, and set properties
  set block_name regmux_2_1
  set block_cell_name regmux_2_1_0
  if { [catch {set regmux_2_1_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $regmux_2_1_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
    set_property CONFIG.DATA_WIDTH {16} $regmux_2_1_0


  # Create instance: axis_broadcaster_cic_path_split, and set properties
  set axis_broadcaster_cic_path_split [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_broadcaster:1.1 axis_broadcaster_cic_path_split ]
  set_property -dict [list \
    CONFIG.M00_TDATA_REMAP {tdata[31:0]} \
    CONFIG.M01_TDATA_REMAP {tdata[63:32]} \
    CONFIG.M_TDATA_NUM_BYTES {4} \
    CONFIG.S_TDATA_NUM_BYTES {8} \
  ] $axis_broadcaster_cic_path_split


  # Create instance: axis_combiner_0, and set properties
  set axis_combiner_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_combiner:1.1 axis_combiner_0 ]
  set_property CONFIG.TDATA_NUM_BYTES {4} $axis_combiner_0


  # Create instance: axis_dwidth_converter_0, and set properties
  set axis_dwidth_converter_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_dwidth_converter:1.1 axis_dwidth_converter_0 ]
  set_property -dict [list \
    CONFIG.HAS_TKEEP {0} \
    CONFIG.HAS_TLAST {0} \
    CONFIG.HAS_TSTRB {0} \
    CONFIG.M_TDATA_NUM_BYTES {3} \
    CONFIG.S_TDATA_NUM_BYTES {6} \
    CONFIG.TDEST_WIDTH {0} \
    CONFIG.TID_WIDTH {0} \
  ] $axis_dwidth_converter_0


  # Create instance: axis_dwidth_converter_fir_to_IQ, and set properties
  set axis_dwidth_converter_fir_to_IQ [ create_bd_cell -type ip -vlnv xilinx.com:ip:axis_dwidth_converter:1.1 axis_dwidth_converter_fir_to_IQ ]
  set_property -dict [list \
    CONFIG.M_TDATA_NUM_BYTES {8} \
    CONFIG.S_TDATA_NUM_BYTES {4} \
  ] $axis_dwidth_converter_fir_to_IQ


  # Create instance: cic_compiler_0, and set properties
  set cic_compiler_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:cic_compiler:4.0 cic_compiler_0 ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {122.88} \
    CONFIG.Fixed_Or_Initial_Rate {80} \
    CONFIG.HAS_ARESETN {true} \
    CONFIG.HAS_DOUT_TREADY {false} \
    CONFIG.Input_Data_Width {27} \
    CONFIG.Input_Sample_Frequency {1.536} \
    CONFIG.Maximum_Rate {320} \
    CONFIG.Minimum_Rate {80} \
    CONFIG.Number_Of_Stages {6} \
    CONFIG.Output_Data_Width {32} \
    CONFIG.Quantization {Truncation} \
    CONFIG.SamplePeriod {80} \
    CONFIG.Sample_Rate_Changes {Programmable} \
    CONFIG.Use_Xtreme_DSP_Slice {false} \
  ] $cic_compiler_0


  # Create instance: cic_compiler_1, and set properties
  set cic_compiler_1 [ create_bd_cell -type ip -vlnv xilinx.com:ip:cic_compiler:4.0 cic_compiler_1 ]
  set_property -dict [list \
    CONFIG.Clock_Frequency {122.88} \
    CONFIG.Fixed_Or_Initial_Rate {80} \
    CONFIG.HAS_ARESETN {true} \
    CONFIG.HAS_DOUT_TREADY {false} \
    CONFIG.Input_Data_Width {27} \
    CONFIG.Input_Sample_Frequency {1.536} \
    CONFIG.Maximum_Rate {320} \
    CONFIG.Minimum_Rate {80} \
    CONFIG.Number_Of_Stages {6} \
    CONFIG.Output_Data_Width {32} \
    CONFIG.Quantization {Truncation} \
    CONFIG.SamplePeriod {80} \
    CONFIG.Sample_Rate_Changes {Programmable} \
    CONFIG.Use_Xtreme_DSP_Slice {false} \
  ] $cic_compiler_1


  # Create instance: cmpy_0, and set properties
  set cmpy_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:cmpy:6.0 cmpy_0 ]
  set_property -dict [list \
    CONFIG.APortWidth {32} \
    CONFIG.BPortWidth {19} \
    CONFIG.FlowControl {NonBlocking} \
    CONFIG.MinimumLatency {9} \
    CONFIG.OutputWidth {24} \
    CONFIG.RoundMode {Random_Rounding} \
  ] $cmpy_0


  # Create instance: dds_compiler_txfreq, and set properties
  set dds_compiler_txfreq [ create_bd_cell -type ip -vlnv xilinx.com:ip:dds_compiler:6.0 dds_compiler_txfreq ]
  set_property -dict [list \
    CONFIG.Amplitude_Mode {Full_Range} \
    CONFIG.DATA_Has_TLAST {Not_Required} \
    CONFIG.DDS_Clock_Rate {122.88} \
    CONFIG.DSP48_Use {Minimal} \
    CONFIG.Frequency_Resolution {0.05} \
    CONFIG.Has_ARESETn {true} \
    CONFIG.Has_Phase_Out {false} \
    CONFIG.Latency {8} \
    CONFIG.M_DATA_Has_TUSER {Not_Required} \
    CONFIG.Noise_Shaping {Taylor_Series_Corrected} \
    CONFIG.Output_Frequency1 {0} \
    CONFIG.Output_Width {19} \
    CONFIG.PINC1 {0} \
    CONFIG.Phase_Increment {Streaming} \
    CONFIG.Phase_Width {32} \
    CONFIG.S_PHASE_Has_TUSER {Not_Required} \
    CONFIG.Spurious_Free_Dynamic_Range {108} \
  ] $dds_compiler_txfreq


  # Create instance: fir_compiler_0, and set properties
  set fir_compiler_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:fir_compiler:7.2 fir_compiler_0 ]
  set_property -dict [list \
    CONFIG.BestPrecision {true} \
    CONFIG.Clock_Frequency {122.88} \
    CONFIG.CoefficientSource {COE_File} \
    CONFIG.Coefficient_File {c:/xilinxdesigns/Saturn/FPGA/sources/coefficientfiles/tx1024cfirImpulse.coe} \
    CONFIG.Coefficient_Fractional_Bits {24} \
    CONFIG.Coefficient_Sets {1} \
    CONFIG.Coefficient_Sign {Signed} \
    CONFIG.Coefficient_Structure {Inferred} \
    CONFIG.Coefficient_Width {22} \
    CONFIG.ColumnConfig {2} \
    CONFIG.DATA_Has_TLAST {Not_Required} \
    CONFIG.Data_Fractional_Bits {0} \
    CONFIG.Data_Width {24} \
    CONFIG.Decimation_Rate {1} \
    CONFIG.Filter_Architecture {Systolic_Multiply_Accumulate} \
    CONFIG.Filter_Type {Interpolation} \
    CONFIG.Has_ARESETn {true} \
    CONFIG.Interpolation_Rate {8} \
    CONFIG.M_DATA_Has_TREADY {true} \
    CONFIG.M_DATA_Has_TUSER {Not_Required} \
    CONFIG.Number_Channels {2} \
    CONFIG.Output_Rounding_Mode {Non_Symmetric_Rounding_Down} \
    CONFIG.Output_Width {27} \
    CONFIG.Quantization {Quantize_Only} \
    CONFIG.RateSpecification {Frequency_Specification} \
    CONFIG.S_DATA_Has_TUSER {Not_Required} \
    CONFIG.Sample_Frequency {0.192} \
    CONFIG.Select_Pattern {All} \
    CONFIG.Zero_Pack_Factor {1} \
  ] $fir_compiler_0


  # Create instance: mult_gen_0, and set properties
  set mult_gen_0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:mult_gen:12.0 mult_gen_0 ]
  set_property -dict [list \
    CONFIG.MultType {Parallel_Multiplier} \
    CONFIG.Multiplier_Construction {Use_Mults} \
    CONFIG.OptGoal {Speed} \
    CONFIG.OutputWidthHigh {32} \
    CONFIG.OutputWidthLow {17} \
    CONFIG.PipeStages {4} \
    CONFIG.PortAWidth {20} \
    CONFIG.PortBType {Unsigned} \
    CONFIG.Use_Custom_Output_Width {true} \
  ] $mult_gen_0


  # Create instance: LFSR_Random_Number_G_0, and set properties
  set block_name LFSR_Random_Number_Generator
  set block_cell_name LFSR_Random_Number_G_0
  if { [catch {set LFSR_Random_Number_G_0 [create_bd_cell -type module -reference $block_name $block_cell_name] } errmsg] } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2095 -severity "ERROR" "Unable to add referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   } elseif { $LFSR_Random_Number_G_0 eq "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2096 -severity "ERROR" "Unable to referenced block <$block_name>. Please add the files for ${block_name}'s definition into the project."}
     return 1
   }
  
  # Create interface connections
  connect_bd_intf_net -intf_net LFSR_Random_Number_G_0_m_axis [get_bd_intf_pins LFSR_Random_Number_G_0/m_axis] [get_bd_intf_pins cmpy_0/S_AXIS_CTRL]
  connect_bd_intf_net -intf_net S_AXIS_1 [get_bd_intf_ports S_AXIS] [get_bd_intf_pins axis_dwidth_converter_0/S_AXIS]
  connect_bd_intf_net -intf_net axis_broadcaster_0_M00_AXIS [get_bd_intf_pins axis_broadcaster_cic_path_split/M00_AXIS] [get_bd_intf_pins cic_compiler_0/S_AXIS_DATA]
  connect_bd_intf_net -intf_net axis_broadcaster_0_M01_AXIS [get_bd_intf_pins axis_broadcaster_cic_path_split/M01_AXIS] [get_bd_intf_pins cic_compiler_1/S_AXIS_DATA]
  connect_bd_intf_net -intf_net axis_combiner_0_M_AXIS [get_bd_intf_pins axis_combiner_0/M_AXIS] [get_bd_intf_pins cmpy_0/S_AXIS_A]
  connect_bd_intf_net -intf_net axis_constant_0_m_axis [get_bd_intf_pins axis_constant_0/m_axis] [get_bd_intf_pins dds_compiler_txfreq/S_AXIS_PHASE]
  connect_bd_intf_net -intf_net axis_dwidth_converter_0_M_AXIS [get_bd_intf_pins axis_dwidth_converter_0/M_AXIS] [get_bd_intf_pins fir_compiler_0/S_AXIS_DATA]
  connect_bd_intf_net -intf_net axis_dwidth_converter_fir_to_IQ_M_AXIS [get_bd_intf_pins axis_broadcaster_cic_path_split/S_AXIS] [get_bd_intf_pins axis_dwidth_converter_fir_to_IQ/M_AXIS]
  connect_bd_intf_net -intf_net axis_variable_0_m_axis [get_bd_intf_pins axis_variable_0/m_axis] [get_bd_intf_pins cic_compiler_0/S_AXIS_CONFIG]
  connect_bd_intf_net -intf_net axis_variable_1_m_axis [get_bd_intf_pins axis_variable_1/m_axis] [get_bd_intf_pins cic_compiler_1/S_AXIS_CONFIG]
  connect_bd_intf_net -intf_net cic_compiler_0_M_AXIS_DATA [get_bd_intf_pins axis_combiner_0/S00_AXIS] [get_bd_intf_pins cic_compiler_0/M_AXIS_DATA]
  connect_bd_intf_net -intf_net cic_compiler_1_M_AXIS_DATA [get_bd_intf_pins axis_combiner_0/S01_AXIS] [get_bd_intf_pins cic_compiler_1/M_AXIS_DATA]
  connect_bd_intf_net -intf_net dds_compiler_txfreq_M_AXIS_DATA [get_bd_intf_pins cmpy_0/S_AXIS_B] [get_bd_intf_pins dds_compiler_txfreq/M_AXIS_DATA]
  connect_bd_intf_net -intf_net fir_compiler_0_M_AXIS_DATA [get_bd_intf_pins axis_dwidth_converter_fir_to_IQ/S_AXIS] [get_bd_intf_pins fir_compiler_0/M_AXIS_DATA]

  # Create port connections
  connect_bd_net -net D_register_2_dout [get_bd_pins D_register_2/dout] [get_bd_ports TXSamplesToRX]
  connect_bd_net -net IQ_Modulation_Select_TX_OPENABLE [get_bd_ports sel] [get_bd_pins regmux_2_1_0/sel]
  connect_bd_net -net Net5 [get_bd_ports clk122] [get_bd_pins D_register_2/aclk] [get_bd_pins axis_constant_0/aclk] [get_bd_pins axis_variable_0/aclk] [get_bd_pins axis_variable_1/aclk] [get_bd_pins cvt_offset_binary_0/clk] [get_bd_pins regmux_2_1_0/aclk] [get_bd_pins axis_broadcaster_cic_path_split/aclk] [get_bd_pins axis_combiner_0/aclk] [get_bd_pins axis_dwidth_converter_0/aclk] [get_bd_pins axis_dwidth_converter_fir_to_IQ/aclk] [get_bd_pins cic_compiler_0/aclk] [get_bd_pins cic_compiler_1/aclk] [get_bd_pins cmpy_0/aclk] [get_bd_pins dds_compiler_txfreq/aclk] [get_bd_pins fir_compiler_0/aclk] [get_bd_pins mult_gen_0/CLK] [get_bd_pins LFSR_Random_Number_G_0/aclk]
  connect_bd_net -net TXConfig_1 [get_bd_ports TXConfig] [get_bd_pins xlslice_3/Din]
  connect_bd_net -net TX_LO_Tune_1 [get_bd_ports TXLOTune] [get_bd_pins axis_constant_0/cfg_data]
  connect_bd_net -net cmpy_0_m_axis_dout_tdata [get_bd_pins cmpy_0/m_axis_dout_tdata] [get_bd_pins xlslice_2/Din]
  connect_bd_net -net cvt_offset_binary_0_dout [get_bd_pins cvt_offset_binary_0/dout] [get_bd_ports TXDACData]
  connect_bd_net -net mult_gen_0_P [get_bd_pins mult_gen_0/P] [get_bd_pins D_register_2/din] [get_bd_pins regmux_2_1_0/din1]
  connect_bd_net -net regmux_2_1_0_dout [get_bd_pins regmux_2_1_0/dout] [get_bd_pins cvt_offset_binary_0/din]
  connect_bd_net -net regmux_2_1_1_dout1 [get_bd_ports cic_rate] [get_bd_pins axis_variable_0/cfg_data] [get_bd_pins axis_variable_1/cfg_data]
  connect_bd_net -net resetn_2 [get_bd_ports resetn1] [get_bd_pins D_register_2/resetn] [get_bd_pins axis_variable_0/aresetn] [get_bd_pins axis_variable_1/aresetn] [get_bd_pins regmux_2_1_0/resetn] [get_bd_pins axis_broadcaster_cic_path_split/aresetn] [get_bd_pins axis_combiner_0/aresetn] [get_bd_pins axis_dwidth_converter_0/aresetn] [get_bd_pins axis_dwidth_converter_fir_to_IQ/aresetn] [get_bd_pins cic_compiler_0/aresetn] [get_bd_pins cic_compiler_1/aresetn] [get_bd_pins dds_compiler_txfreq/aresetn] [get_bd_pins fir_compiler_0/aresetn] [get_bd_pins LFSR_Random_Number_G_0/aresetn]
  connect_bd_net -net xlconstant_16x0_dout [get_bd_pins xlconstant_16x0/dout] [get_bd_pins regmux_2_1_0/din0]
  connect_bd_net -net xlslice_2_Dout [get_bd_pins xlslice_2/Dout] [get_bd_pins mult_gen_0/A]
  connect_bd_net -net xlslice_3_Dout [get_bd_pins xlslice_3/Dout] [get_bd_pins mult_gen_0/B]

  # Create address segments


  # Restore current instance
  current_bd_instance $oldCurInst

  validate_bd_design
  save_bd_design
}
# End of create_root_design()


##################################################################
# MAIN FLOW
##################################################################

create_root_design ""


