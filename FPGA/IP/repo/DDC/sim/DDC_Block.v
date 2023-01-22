//Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2021.2 (win64) Build 3367213 Tue Oct 19 02:48:09 MDT 2021
//Date        : Sun Jan  8 14:25:15 2023
//Host        : CCLDesktop running 64-bit major release  (build 9200)
//Command     : generate_target DDC_Block.bd
//Design      : DDC_Block
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CORE_GENERATION_INFO = "DDC_Block,IP_Integrator,{x_ipVendor=xilinx.com,x_ipLibrary=BlockDiagram,x_ipName=DDC_Block,x_ipVersion=1.00.a,x_ipLanguage=VERILOG,numBlks=33,numReposBlks=33,numNonXlnxBlks=0,numHierBlks=0,maxHierDepth=0,numSysgenBlks=0,numHlsBlks=0,numHdlrefBlks=10,numPkgbdBlks=0,bdsource=USER,synth_mode=OOC_per_IP}" *) (* HW_HANDOFF = "DDC_Block.hwdef" *) 
module DDC_Block
   (Byteswap,
    ChanConfig,
    ChanFreq,
    CicInterp,
    LOIQIn_tdata,
    LOIQIn_tdest,
    LOIQIn_tid,
    LOIQIn_tkeep,
    LOIQIn_tlast,
    LOIQIn_tready,
    LOIQIn_tuser,
    LOIQIn_tvalid,
    LOIQOut_tdata,
    LOIQOut_tvalid,
    LOIQSel,
    M_AXIS_DATA_tdata,
    M_AXIS_DATA_tready,
    M_AXIS_DATA_tvalid,
    aclk,
    adc1,
    adc2,
    rstn,
    test_source,
    tx_samples);
  input Byteswap;
  input [1:0]ChanConfig;
  input [31:0]ChanFreq;
  input [2:0]CicInterp;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 LOIQIn TDATA" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME LOIQIn, CLK_DOMAIN DDC_Block_aclk, FREQ_HZ 122880000, HAS_TKEEP 0, HAS_TLAST 0, HAS_TREADY 1, HAS_TSTRB 0, INSERT_VIP 0, LAYERED_METADATA undef, PHASE 0.0, TDATA_NUM_BYTES 4, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0" *) input [31:0]LOIQIn_tdata;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 LOIQIn TDEST" *) input [7:0]LOIQIn_tdest;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 LOIQIn TID" *) input [7:0]LOIQIn_tid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 LOIQIn TKEEP" *) input [0:0]LOIQIn_tkeep;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 LOIQIn TLAST" *) input LOIQIn_tlast;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 LOIQIn TREADY" *) output LOIQIn_tready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 LOIQIn TUSER" *) input [0:0]LOIQIn_tuser;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 LOIQIn TVALID" *) input LOIQIn_tvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 LOIQOut TDATA" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME LOIQOut, CLK_DOMAIN DDC_Block_aclk, FREQ_HZ 122880000, HAS_TKEEP 0, HAS_TLAST 0, HAS_TREADY 0, HAS_TSTRB 0, INSERT_VIP 0, LAYERED_METADATA undef, PHASE 0.0, TDATA_NUM_BYTES 4, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0" *) output [31:0]LOIQOut_tdata;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 LOIQOut TVALID" *) output [0:0]LOIQOut_tvalid;
  input LOIQSel;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_DATA TDATA" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXIS_DATA, CLK_DOMAIN DDC_Block_aclk, FREQ_HZ 122880000, HAS_TKEEP 0, HAS_TLAST 0, HAS_TREADY 1, HAS_TSTRB 0, INSERT_VIP 0, LAYERED_METADATA undef, PHASE 0.0, TDATA_NUM_BYTES 6, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0" *) output [47:0]M_AXIS_DATA_tdata;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_DATA TREADY" *) input M_AXIS_DATA_tready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_DATA TVALID" *) output M_AXIS_DATA_tvalid;
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 CLK.ACLK CLK" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME CLK.ACLK, ASSOCIATED_BUSIF M_AXIS_DATA:LOIQOut:LOIQIn, ASSOCIATED_RESET rstn, CLK_DOMAIN DDC_Block_aclk, FREQ_HZ 122880000, FREQ_TOLERANCE_HZ 0, INSERT_VIP 0, PHASE 0.0" *) input aclk;
  input [15:0]adc1;
  input [15:0]adc2;
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 RST.RSTN RST" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME RST.RSTN, INSERT_VIP 0, POLARITY ACTIVE_LOW" *) input rstn;
  input [15:0]test_source;
  input [15:0]tx_samples;

  wire Byteswap_1;
  wire [31:0]ChanFreq_1;
  wire [2:0]CicInterp_1;
  wire [8:0]Double_D_register_0_dout;
  wire [16:0]HalfLSBAdder_0_output_data;
  wire [31:0]LOIQIn_1_TDATA;
  wire [7:0]LOIQIn_1_TDEST;
  wire [7:0]LOIQIn_1_TID;
  wire [0:0]LOIQIn_1_TKEEP;
  wire LOIQIn_1_TLAST;
  wire LOIQIn_1_TREADY;
  wire [0:0]LOIQIn_1_TUSER;
  wire LOIQIn_1_TVALID;
  wire LOIQSel_1;
  wire aclk_1;
  wire [15:0]adc1_1;
  wire [15:0]adc2_1;
  wire [31:0]axis_broadcaster_0_M00_AXIS_TDATA;
  wire [0:0]axis_broadcaster_0_M00_AXIS_TVALID;
  wire [63:32]axis_broadcaster_0_M01_AXIS_TDATA;
  wire [1:1]axis_broadcaster_0_M01_AXIS_TVALID;
  wire [23:0]axis_broadcaster_1_M00_AXIS_TDATA;
  wire [0:0]axis_broadcaster_1_M00_AXIS_TVALID;
  wire [47:24]axis_broadcaster_1_M01_AXIS_TDATA;
  wire [1:1]axis_broadcaster_1_M01_AXIS_TVALID;
  wire [47:0]axis_combiner_0_M_AXIS_TDATA;
  wire axis_combiner_0_M_AXIS_TREADY;
  wire axis_combiner_0_M_AXIS_TVALID;
  wire [23:0]axis_dwidth_converter_0_M_AXIS_TDATA;
  wire axis_dwidth_converter_0_M_AXIS_TREADY;
  wire axis_dwidth_converter_0_M_AXIS_TVALID;
  wire [47:0]axis_dwidth_converter_1_M_AXIS_TDATA;
  wire axis_dwidth_converter_1_M_AXIS_TREADY;
  wire axis_dwidth_converter_1_M_AXIS_TVALID;
  wire [31:0]axis_mux_2_0_output_axis_TDATA;
  wire axis_mux_2_0_output_axis_TVALID;
  wire [23:0]axis_subset_converter_0_M_AXIS_TDATA;
  wire axis_subset_converter_0_M_AXIS_TREADY;
  wire axis_subset_converter_0_M_AXIS_TVALID;
  wire [23:0]axis_subset_converter_1_M_AXIS_TDATA;
  wire axis_subset_converter_1_M_AXIS_TVALID;
  wire [23:0]axis_subset_converter_2_M_AXIS_TDATA;
  wire axis_subset_converter_2_M_AXIS_TVALID;
  wire [15:0]axis_variable_0_m_axis_TDATA;
  wire axis_variable_0_m_axis_TREADY;
  wire axis_variable_0_m_axis_TVALID;
  wire [15:0]axis_variable_1_m_axis_TDATA;
  wire axis_variable_1_m_axis_TREADY;
  wire axis_variable_1_m_axis_TVALID;
  wire [47:0]byteswap_48_0_m_axis_TDATA;
  wire byteswap_48_0_m_axis_TREADY;
  wire byteswap_48_0_m_axis_TVALID;
  wire [47:0]cic_compiler_0_M_AXIS_DATA_TDATA;
  wire cic_compiler_0_M_AXIS_DATA_TVALID;
  wire [47:0]cic_compiler_1_M_AXIS_DATA_TDATA;
  wire cic_compiler_1_M_AXIS_DATA_TVALID;
  wire [47:0]cmpy_0_M_AXIS_DOUT_TDATA;
  wire cmpy_0_M_AXIS_DOUT_TVALID;
  wire [31:0]dds_compiler_0_M_AXIS_DATA_TDATA;
  wire dds_compiler_0_M_AXIS_DATA_TVALID;
  wire [31:0]fir_compiler_0_M_AXIS_DATA_TDATA;
  wire fir_compiler_0_M_AXIS_DATA_TREADY;
  wire fir_compiler_0_M_AXIS_DATA_TVALID;
  wire [31:0]reg_to_axis_0_m_axis_TDATA;
  wire reg_to_axis_0_m_axis_TVALID;
  wire [47:0]reg_to_axis_1_m_axis_TDATA;
  wire reg_to_axis_1_m_axis_TVALID;
  wire [15:0]regmux_4_1_0_dout;
  wire [8:0]regmux_8_1_0_dout;
  wire rstn_1;
  wire [1:0]sel_0_1;
  wire [15:0]test_source_1;
  wire [15:0]tx_samples_1;
  wire [15:0]xlconcat_1_dout;
  wire [47:0]xlconcat_2_dout;
  wire [8:0]xlconstant_10_dout;
  wire [8:0]xlconstant_160_dout;
  wire [30:0]xlconstant_16bits0_dout;
  wire [8:0]xlconstant_20_dout;
  wire [8:0]xlconstant_320_dout;
  wire [8:0]xlconstant_40_dout;
  wire [6:0]xlconstant_7bits0_dout;
  wire [8:0]xlconstant_80_dout;

  assign Byteswap_1 = Byteswap;
  assign ChanFreq_1 = ChanFreq[31:0];
  assign CicInterp_1 = CicInterp[2:0];
  assign LOIQIn_1_TDATA = LOIQIn_tdata[31:0];
  assign LOIQIn_1_TDEST = LOIQIn_tdest[7:0];
  assign LOIQIn_1_TID = LOIQIn_tid[7:0];
  assign LOIQIn_1_TKEEP = LOIQIn_tkeep[0];
  assign LOIQIn_1_TLAST = LOIQIn_tlast;
  assign LOIQIn_1_TUSER = LOIQIn_tuser[0];
  assign LOIQIn_1_TVALID = LOIQIn_tvalid;
  assign LOIQIn_tready = LOIQIn_1_TREADY;
  assign LOIQOut_tdata[31:0] = axis_broadcaster_0_M01_AXIS_TDATA;
  assign LOIQOut_tvalid[0] = axis_broadcaster_0_M01_AXIS_TVALID;
  assign LOIQSel_1 = LOIQSel;
  assign M_AXIS_DATA_tdata[47:0] = byteswap_48_0_m_axis_TDATA;
  assign M_AXIS_DATA_tvalid = byteswap_48_0_m_axis_TVALID;
  assign aclk_1 = aclk;
  assign adc1_1 = adc1[15:0];
  assign adc2_1 = adc2[15:0];
  assign byteswap_48_0_m_axis_TREADY = M_AXIS_DATA_tready;
  assign rstn_1 = rstn;
  assign sel_0_1 = ChanConfig[1:0];
  assign test_source_1 = test_source[15:0];
  assign tx_samples_1 = tx_samples[15:0];
  DDC_Block_Double_D_register_0_0 Double_D_register_0
       (.aclk(aclk_1),
        .din(regmux_8_1_0_dout),
        .dout(Double_D_register_0_dout));
  DDC_Block_HalfLSBAdder_0_0 HalfLSBAdder_0
       (.aclk(aclk_1),
        .input_data(regmux_4_1_0_dout),
        .output_data(HalfLSBAdder_0_output_data));
  DDC_Block_axis_broadcaster_0_0 axis_broadcaster_0
       (.aclk(aclk_1),
        .aresetn(rstn_1),
        .m_axis_tdata({axis_broadcaster_0_M01_AXIS_TDATA,axis_broadcaster_0_M00_AXIS_TDATA}),
        .m_axis_tvalid({axis_broadcaster_0_M01_AXIS_TVALID,axis_broadcaster_0_M00_AXIS_TVALID}),
        .s_axis_tdata(dds_compiler_0_M_AXIS_DATA_TDATA),
        .s_axis_tvalid(dds_compiler_0_M_AXIS_DATA_TVALID));
  DDC_Block_axis_broadcaster_1_0 axis_broadcaster_1
       (.aclk(aclk_1),
        .aresetn(rstn_1),
        .m_axis_tdata({axis_broadcaster_1_M01_AXIS_TDATA,axis_broadcaster_1_M00_AXIS_TDATA}),
        .m_axis_tvalid({axis_broadcaster_1_M01_AXIS_TVALID,axis_broadcaster_1_M00_AXIS_TVALID}),
        .s_axis_tdata(cmpy_0_M_AXIS_DOUT_TDATA),
        .s_axis_tvalid(cmpy_0_M_AXIS_DOUT_TVALID));
  DDC_Block_axis_combiner_0_0 axis_combiner_0
       (.aclk(aclk_1),
        .aresetn(rstn_1),
        .m_axis_tdata(axis_combiner_0_M_AXIS_TDATA),
        .m_axis_tready(axis_combiner_0_M_AXIS_TREADY),
        .m_axis_tvalid(axis_combiner_0_M_AXIS_TVALID),
        .s_axis_tdata({axis_subset_converter_2_M_AXIS_TDATA,axis_subset_converter_1_M_AXIS_TDATA}),
        .s_axis_tvalid({axis_subset_converter_2_M_AXIS_TVALID,axis_subset_converter_1_M_AXIS_TVALID}));
  DDC_Block_axis_dwidth_converter_0_0 axis_dwidth_converter_0
       (.aclk(aclk_1),
        .aresetn(rstn_1),
        .m_axis_tdata(axis_dwidth_converter_0_M_AXIS_TDATA),
        .m_axis_tready(axis_dwidth_converter_0_M_AXIS_TREADY),
        .m_axis_tvalid(axis_dwidth_converter_0_M_AXIS_TVALID),
        .s_axis_tdata(axis_combiner_0_M_AXIS_TDATA),
        .s_axis_tready(axis_combiner_0_M_AXIS_TREADY),
        .s_axis_tvalid(axis_combiner_0_M_AXIS_TVALID));
  DDC_Block_axis_dwidth_converter_1_0 axis_dwidth_converter_1
       (.aclk(aclk_1),
        .aresetn(rstn_1),
        .m_axis_tdata(axis_dwidth_converter_1_M_AXIS_TDATA),
        .m_axis_tready(axis_dwidth_converter_1_M_AXIS_TREADY),
        .m_axis_tvalid(axis_dwidth_converter_1_M_AXIS_TVALID),
        .s_axis_tdata(axis_subset_converter_0_M_AXIS_TDATA),
        .s_axis_tready(axis_subset_converter_0_M_AXIS_TREADY),
        .s_axis_tvalid(axis_subset_converter_0_M_AXIS_TVALID));
  DDC_Block_axis_mux_2_0_0 axis_mux_2_0
       (.clk(aclk_1),
        .input_0_axis_tdata(axis_broadcaster_0_M00_AXIS_TDATA),
        .input_0_axis_tdest({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .input_0_axis_tid({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .input_0_axis_tkeep(1'b1),
        .input_0_axis_tlast(1'b0),
        .input_0_axis_tuser(1'b0),
        .input_0_axis_tvalid(axis_broadcaster_0_M00_AXIS_TVALID),
        .input_1_axis_tdata(LOIQIn_1_TDATA),
        .input_1_axis_tdest(LOIQIn_1_TDEST),
        .input_1_axis_tid(LOIQIn_1_TID),
        .input_1_axis_tkeep(LOIQIn_1_TKEEP),
        .input_1_axis_tlast(LOIQIn_1_TLAST),
        .input_1_axis_tready(LOIQIn_1_TREADY),
        .input_1_axis_tuser(LOIQIn_1_TUSER),
        .input_1_axis_tvalid(LOIQIn_1_TVALID),
        .output_axis_tdata(axis_mux_2_0_output_axis_TDATA),
        .output_axis_tready(1'b1),
        .output_axis_tvalid(axis_mux_2_0_output_axis_TVALID),
        .rstn(rstn_1),
        .sel(LOIQSel_1));
  DDC_Block_axis_subset_converter_0_0 axis_subset_converter_0
       (.aclk(aclk_1),
        .aresetn(rstn_1),
        .m_axis_tdata(axis_subset_converter_0_M_AXIS_TDATA),
        .m_axis_tready(axis_subset_converter_0_M_AXIS_TREADY),
        .m_axis_tvalid(axis_subset_converter_0_M_AXIS_TVALID),
        .s_axis_tdata(fir_compiler_0_M_AXIS_DATA_TDATA),
        .s_axis_tready(fir_compiler_0_M_AXIS_DATA_TREADY),
        .s_axis_tvalid(fir_compiler_0_M_AXIS_DATA_TVALID));
  DDC_Block_axis_subset_converter_1_0 axis_subset_converter_1
       (.aclk(aclk_1),
        .aresetn(rstn_1),
        .m_axis_tdata(axis_subset_converter_1_M_AXIS_TDATA),
        .m_axis_tvalid(axis_subset_converter_1_M_AXIS_TVALID),
        .s_axis_tdata(cic_compiler_1_M_AXIS_DATA_TDATA),
        .s_axis_tvalid(cic_compiler_1_M_AXIS_DATA_TVALID));
  DDC_Block_axis_subset_converter_1_1 axis_subset_converter_2
       (.aclk(aclk_1),
        .aresetn(rstn_1),
        .m_axis_tdata(axis_subset_converter_2_M_AXIS_TDATA),
        .m_axis_tvalid(axis_subset_converter_2_M_AXIS_TVALID),
        .s_axis_tdata(cic_compiler_0_M_AXIS_DATA_TDATA),
        .s_axis_tvalid(cic_compiler_0_M_AXIS_DATA_TVALID));
  DDC_Block_axis_variable_0_0 axis_variable_0
       (.aclk(aclk_1),
        .aresetn(rstn_1),
        .cfg_data(xlconcat_1_dout),
        .m_axis_tdata(axis_variable_0_m_axis_TDATA),
        .m_axis_tready(axis_variable_0_m_axis_TREADY),
        .m_axis_tvalid(axis_variable_0_m_axis_TVALID));
  DDC_Block_axis_variable_1_0 axis_variable_1
       (.aclk(aclk_1),
        .aresetn(rstn_1),
        .cfg_data(xlconcat_1_dout),
        .m_axis_tdata(axis_variable_1_m_axis_TDATA),
        .m_axis_tready(axis_variable_1_m_axis_TREADY),
        .m_axis_tvalid(axis_variable_1_m_axis_TVALID));
  DDC_Block_byteswap_48_0_0 byteswap_48_0
       (.aclk(aclk_1),
        .aresetn(rstn_1),
        .m_axis_tdata(byteswap_48_0_m_axis_TDATA),
        .m_axis_tready(byteswap_48_0_m_axis_TREADY),
        .m_axis_tvalid(byteswap_48_0_m_axis_TVALID),
        .s_axis_tdata(axis_dwidth_converter_1_M_AXIS_TDATA),
        .s_axis_tready(axis_dwidth_converter_1_M_AXIS_TREADY),
        .s_axis_tvalid(axis_dwidth_converter_1_M_AXIS_TVALID),
        .swap(Byteswap_1));
  DDC_Block_cic_compiler_0_0 cic_compiler_0
       (.aclk(aclk_1),
        .aresetn(rstn_1),
        .m_axis_data_tdata(cic_compiler_0_M_AXIS_DATA_TDATA),
        .m_axis_data_tvalid(cic_compiler_0_M_AXIS_DATA_TVALID),
        .s_axis_config_tdata(axis_variable_1_m_axis_TDATA),
        .s_axis_config_tready(axis_variable_1_m_axis_TREADY),
        .s_axis_config_tvalid(axis_variable_1_m_axis_TVALID),
        .s_axis_data_tdata(axis_broadcaster_1_M01_AXIS_TDATA),
        .s_axis_data_tvalid(axis_broadcaster_1_M01_AXIS_TVALID));
  DDC_Block_cic_compiler_1_0 cic_compiler_1
       (.aclk(aclk_1),
        .aresetn(rstn_1),
        .m_axis_data_tdata(cic_compiler_1_M_AXIS_DATA_TDATA),
        .m_axis_data_tvalid(cic_compiler_1_M_AXIS_DATA_TVALID),
        .s_axis_config_tdata(axis_variable_0_m_axis_TDATA),
        .s_axis_config_tready(axis_variable_0_m_axis_TREADY),
        .s_axis_config_tvalid(axis_variable_0_m_axis_TVALID),
        .s_axis_data_tdata(axis_broadcaster_1_M00_AXIS_TDATA),
        .s_axis_data_tvalid(axis_broadcaster_1_M00_AXIS_TVALID));
  DDC_Block_cmpy_0_0 cmpy_0
       (.aclk(aclk_1),
        .m_axis_dout_tdata(cmpy_0_M_AXIS_DOUT_TDATA),
        .m_axis_dout_tvalid(cmpy_0_M_AXIS_DOUT_TVALID),
        .s_axis_a_tdata(reg_to_axis_1_m_axis_TDATA),
        .s_axis_a_tvalid(reg_to_axis_1_m_axis_TVALID),
        .s_axis_b_tdata(axis_mux_2_0_output_axis_TDATA),
        .s_axis_b_tvalid(axis_mux_2_0_output_axis_TVALID));
  DDC_Block_dds_compiler_0_0 dds_compiler_0
       (.aclk(aclk_1),
        .aresetn(rstn_1),
        .m_axis_data_tdata(dds_compiler_0_M_AXIS_DATA_TDATA),
        .m_axis_data_tvalid(dds_compiler_0_M_AXIS_DATA_TVALID),
        .s_axis_phase_tdata(reg_to_axis_0_m_axis_TDATA),
        .s_axis_phase_tvalid(reg_to_axis_0_m_axis_TVALID));
  DDC_Block_fir_compiler_0_0 fir_compiler_0
       (.aclk(aclk_1),
        .aresetn(rstn_1),
        .m_axis_data_tdata(fir_compiler_0_M_AXIS_DATA_TDATA),
        .m_axis_data_tready(fir_compiler_0_M_AXIS_DATA_TREADY),
        .m_axis_data_tvalid(fir_compiler_0_M_AXIS_DATA_TVALID),
        .s_axis_data_tdata(axis_dwidth_converter_0_M_AXIS_TDATA),
        .s_axis_data_tready(axis_dwidth_converter_0_M_AXIS_TREADY),
        .s_axis_data_tvalid(axis_dwidth_converter_0_M_AXIS_TVALID));
  DDC_Block_reg_to_axis_0_0 reg_to_axis_0
       (.aclk(aclk_1),
        .data_in(ChanFreq_1),
        .m_axis_tdata(reg_to_axis_0_m_axis_TDATA),
        .m_axis_tvalid(reg_to_axis_0_m_axis_TVALID));
  DDC_Block_reg_to_axis_1_0 reg_to_axis_1
       (.aclk(aclk_1),
        .data_in(xlconcat_2_dout),
        .m_axis_tdata(reg_to_axis_1_m_axis_TDATA),
        .m_axis_tvalid(reg_to_axis_1_m_axis_TVALID));
  DDC_Block_regmux_4_1_0_0 regmux_4_1_0
       (.aclk(aclk_1),
        .din0(adc1_1),
        .din1(adc2_1),
        .din2(test_source_1),
        .din3(tx_samples_1),
        .dout(regmux_4_1_0_dout),
        .resetn(rstn_1),
        .sel(sel_0_1));
  DDC_Block_regmux_8_1_0_0 regmux_8_1_0
       (.aclk(aclk_1),
        .din0(xlconstant_320_dout),
        .din1(xlconstant_320_dout),
        .din2(xlconstant_160_dout),
        .din3(xlconstant_80_dout),
        .din4(xlconstant_40_dout),
        .din5(xlconstant_20_dout),
        .din6(xlconstant_10_dout),
        .din7(xlconstant_10_dout),
        .dout(regmux_8_1_0_dout),
        .resetn(rstn_1),
        .sel(CicInterp_1));
  DDC_Block_xlconcat_1_0 xlconcat_1
       (.In0(Double_D_register_0_dout),
        .In1(xlconstant_7bits0_dout),
        .dout(xlconcat_1_dout));
  DDC_Block_xlconcat_2_0 xlconcat_2
       (.In0(HalfLSBAdder_0_output_data),
        .In1(xlconstant_16bits0_dout),
        .dout(xlconcat_2_dout));
  DDC_Block_xlconstant_10_0 xlconstant_10
       (.dout(xlconstant_10_dout));
  DDC_Block_xlconstant_160_0 xlconstant_160
       (.dout(xlconstant_160_dout));
  DDC_Block_xlconstant_16bits0_0 xlconstant_16bits0
       (.dout(xlconstant_16bits0_dout));
  DDC_Block_xlconstant_20_0 xlconstant_20
       (.dout(xlconstant_20_dout));
  DDC_Block_xlconstant_320_0 xlconstant_320
       (.dout(xlconstant_320_dout));
  DDC_Block_xlconstant_40_0 xlconstant_40
       (.dout(xlconstant_40_dout));
  DDC_Block_xlconstant_7bits0_0 xlconstant_7bits0
       (.dout(xlconstant_7bits0_dout));
  DDC_Block_xlconstant_80_0 xlconstant_80
       (.dout(xlconstant_80_dout));
endmodule
