// (c) Copyright 1995-2022 Xilinx, Inc. All rights reserved.
// 
// This file contains confidential and proprietary information
// of Xilinx, Inc. and is protected under U.S. and
// international copyright and other intellectual property
// laws.
// 
// DISCLAIMER
// This disclaimer is not a license and does not grant any
// rights to the materials distributed herewith. Except as
// otherwise provided in a valid license issued to you by
// Xilinx, and to the maximum extent permitted by applicable
// law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
// WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
// AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
// BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
// INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
// (2) Xilinx shall not be liable (whether in contract or tort,
// including negligence, or under any other theory of
// liability) for any loss or damage of any kind or nature
// related to, arising under or in connection with these
// materials, including for any direct, or any indirect,
// special, incidental, or consequential loss or damage
// (including loss of data, profits, goodwill, or any type of
// loss or damage suffered as a result of any action brought
// by a third party) even if such damage or loss was
// reasonably foreseeable or Xilinx had been advised of the
// possibility of the same.
// 
// CRITICAL APPLICATIONS
// Xilinx products are not designed or intended to be fail-
// safe, or for use in any application requiring fail-safe
// performance, such as life-support or safety devices or
// systems, Class III medical devices, nuclear facilities,
// applications related to the deployment of airbags, or any
// other applications that could lead to death, personal
// injury, or severe property or environmental damage
// (individually and collectively, "Critical
// Applications"). Customer assumes the sole risk and
// liability of any use of Xilinx products in Critical
// Applications, subject only to applicable laws and
// regulations governing limitations on product liability.
// 
// THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
// PART OF THIS FILE AT ALL TIMES.
// 
// DO NOT MODIFY THIS FILE.


// IP VLNV: xilinx.com:module_ref:axis_mux_2:1.0
// IP Revision: 1

`timescale 1ns/1ps

(* IP_DEFINITION_SOURCE = "module_ref" *)
(* DowngradeIPIdentifiedWarnings = "yes" *)
module DDC_Block_axis_mux_2_0_0 (
  clk,
  rstn,
  input_0_axis_tdata,
  input_0_axis_tkeep,
  input_0_axis_tvalid,
  input_0_axis_tready,
  input_0_axis_tlast,
  input_0_axis_tid,
  input_0_axis_tdest,
  input_0_axis_tuser,
  input_1_axis_tdata,
  input_1_axis_tkeep,
  input_1_axis_tvalid,
  input_1_axis_tready,
  input_1_axis_tlast,
  input_1_axis_tid,
  input_1_axis_tdest,
  input_1_axis_tuser,
  output_axis_tdata,
  output_axis_tkeep,
  output_axis_tvalid,
  output_axis_tready,
  output_axis_tlast,
  output_axis_tid,
  output_axis_tdest,
  output_axis_tuser,
  sel
);

(* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk, ASSOCIATED_BUSIF input_0_axis:input_1_axis:output_axis, ASSOCIATED_RESET rstn, FREQ_HZ 122880000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN DDC_Block_aclk, INSERT_VIP 0" *)
(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
input wire clk;
(* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME rstn, POLARITY ACTIVE_LOW, INSERT_VIP 0" *)
(* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rstn RST" *)
input wire rstn;
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 input_0_axis TDATA" *)
input wire [31 : 0] input_0_axis_tdata;
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 input_0_axis TKEEP" *)
input wire [0 : 0] input_0_axis_tkeep;
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 input_0_axis TVALID" *)
input wire input_0_axis_tvalid;
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 input_0_axis TREADY" *)
output wire input_0_axis_tready;
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 input_0_axis TLAST" *)
input wire input_0_axis_tlast;
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 input_0_axis TID" *)
input wire [7 : 0] input_0_axis_tid;
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 input_0_axis TDEST" *)
input wire [7 : 0] input_0_axis_tdest;
(* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME input_0_axis, TDATA_NUM_BYTES 4, TDEST_WIDTH 8, TID_WIDTH 8, TUSER_WIDTH 1, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 1, HAS_TLAST 1, FREQ_HZ 122880000, PHASE 0.0, CLK_DOMAIN DDC_Block_aclk, LAYERED_METADATA undef, INSERT_VIP 0" *)
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 input_0_axis TUSER" *)
input wire [0 : 0] input_0_axis_tuser;
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 input_1_axis TDATA" *)
input wire [31 : 0] input_1_axis_tdata;
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 input_1_axis TKEEP" *)
input wire [0 : 0] input_1_axis_tkeep;
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 input_1_axis TVALID" *)
input wire input_1_axis_tvalid;
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 input_1_axis TREADY" *)
output wire input_1_axis_tready;
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 input_1_axis TLAST" *)
input wire input_1_axis_tlast;
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 input_1_axis TID" *)
input wire [7 : 0] input_1_axis_tid;
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 input_1_axis TDEST" *)
input wire [7 : 0] input_1_axis_tdest;
(* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME input_1_axis, TDATA_NUM_BYTES 4, TDEST_WIDTH 8, TID_WIDTH 8, TUSER_WIDTH 1, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 1, HAS_TLAST 1, FREQ_HZ 122880000, PHASE 0.0, CLK_DOMAIN DDC_Block_aclk, LAYERED_METADATA undef, INSERT_VIP 0" *)
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 input_1_axis TUSER" *)
input wire [0 : 0] input_1_axis_tuser;
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 output_axis TDATA" *)
output wire [31 : 0] output_axis_tdata;
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 output_axis TKEEP" *)
output wire [0 : 0] output_axis_tkeep;
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 output_axis TVALID" *)
output wire output_axis_tvalid;
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 output_axis TREADY" *)
input wire output_axis_tready;
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 output_axis TLAST" *)
output wire output_axis_tlast;
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 output_axis TID" *)
output wire [7 : 0] output_axis_tid;
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 output_axis TDEST" *)
output wire [7 : 0] output_axis_tdest;
(* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME output_axis, TDATA_NUM_BYTES 4, TDEST_WIDTH 8, TID_WIDTH 8, TUSER_WIDTH 1, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 1, HAS_TLAST 1, FREQ_HZ 122880000, PHASE 0.0, CLK_DOMAIN DDC_Block_aclk, LAYERED_METADATA undef, INSERT_VIP 0" *)
(* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 output_axis TUSER" *)
output wire [0 : 0] output_axis_tuser;
input wire sel;

  axis_mux_2 #(
    .DATA_WIDTH(32),
    .KEEP_ENABLE(1'B0),
    .KEEP_WIDTH(1),
    .ID_ENABLE(0),
    .ID_WIDTH(8),
    .DEST_ENABLE(0),
    .DEST_WIDTH(0),
    .USER_ENABLE(1),
    .USER_WIDTH(1),
    .CONSUME_ALL(1)
  ) inst (
    .clk(clk),
    .rstn(rstn),
    .input_0_axis_tdata(input_0_axis_tdata),
    .input_0_axis_tkeep(input_0_axis_tkeep),
    .input_0_axis_tvalid(input_0_axis_tvalid),
    .input_0_axis_tready(input_0_axis_tready),
    .input_0_axis_tlast(input_0_axis_tlast),
    .input_0_axis_tid(input_0_axis_tid),
    .input_0_axis_tdest(input_0_axis_tdest),
    .input_0_axis_tuser(input_0_axis_tuser),
    .input_1_axis_tdata(input_1_axis_tdata),
    .input_1_axis_tkeep(input_1_axis_tkeep),
    .input_1_axis_tvalid(input_1_axis_tvalid),
    .input_1_axis_tready(input_1_axis_tready),
    .input_1_axis_tlast(input_1_axis_tlast),
    .input_1_axis_tid(input_1_axis_tid),
    .input_1_axis_tdest(input_1_axis_tdest),
    .input_1_axis_tuser(input_1_axis_tuser),
    .output_axis_tdata(output_axis_tdata),
    .output_axis_tkeep(output_axis_tkeep),
    .output_axis_tvalid(output_axis_tvalid),
    .output_axis_tready(output_axis_tready),
    .output_axis_tlast(output_axis_tlast),
    .output_axis_tid(output_axis_tid),
    .output_axis_tdest(output_axis_tdest),
    .output_axis_tuser(output_axis_tuser),
    .sel(sel)
  );
endmodule
