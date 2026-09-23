`timescale 1ns / 1ps
// SOURCES: axil_SPIWriter.v
//////////////////////////////////////////////////////////////////////////////////
// Module Name:    tb_axil_spiwriter
// Description:    self checking test of AXIL_SPIWriter (codec SPI)
//                 - write to 0x0 shifts out the 16 bit word and captures MISO
//                 - writes to 0x4 / 0x8 / 0xC must complete (no bus hang) and
//                   must not start an SPI shift
//                 - read data must stay stable under RREADY back-pressure
//////////////////////////////////////////////////////////////////////////////////

module tb_axil_spiwriter;

  reg aclk = 0;
  reg aresetn = 0;
  always #4 aclk = ~aclk;

  wire [15:0] awaddr, araddr;
  wire awvalid, awready, wvalid, wready, bvalid, bready, arvalid, arready, rvalid, rready;
  wire [31:0] wdata, rdata;
  wire [3:0]  wstrb;
  wire [1:0]  bresp, rresp;
  wire SPICk, SPIData, SPILoad;
  reg  SPIMISO = 0;

  axil_master_bfm #(.ADDR_WIDTH(16), .DATA_WIDTH(32)) bfm (
    .aclk(aclk), .awaddr(awaddr), .awvalid(awvalid), .awready(awready), .wdata(wdata), .wstrb(wstrb),
    .wvalid(wvalid), .wready(wready), .bresp(bresp), .bvalid(bvalid), .bready(bready),
    .araddr(araddr), .arvalid(arvalid), .arready(arready), .rdata(rdata), .rresp(rresp),
    .rvalid(rvalid), .rready(rready));

  axil_checker #(.DATA_WIDTH(32), .NAME("spiwriter")) chk (
    .aclk(aclk), .aresetn(aresetn), .awready(awready), .wready(wready), .bvalid(bvalid), .bready(bready),
    .arready(arready), .rdata(rdata), .rresp(rresp), .rvalid(rvalid), .rready(rready));

  AXIL_SPIWriter #(.AXI_DATA_WIDTH(32), .AXI_ADDR_WIDTH(16), .SPI_CLOCK_DIVIDE(3)) dut (
    .aclk(aclk), .aresetn(aresetn),
    .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
    .s_axi_wdata(wdata), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
    .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
    .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
    .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
    .SPICk(SPICk), .SPIData(SPIData), .SPILoad(SPILoad), .SPIMISO(SPIMISO));

//
// SPI slave model: capture MOSI on rising SPICk, drive MISO pattern MSB first,
// next bit presented after each falling SPICk
//
  reg  [15:0] mosi_word = 0;
  reg  [15:0] miso_pattern = 16'hA5C3;
  integer     bitcount = 0;
  integer     frames = 0;
  always @(negedge SPILoad) begin bitcount = 0; SPIMISO = miso_pattern[15]; end
  always @(posedge SPICk) if(!SPILoad) begin mosi_word = {mosi_word[14:0], SPIData}; end
  always @(negedge SPICk) if(!SPILoad) begin bitcount = bitcount + 1; if(bitcount < 16) SPIMISO = miso_pattern[15-bitcount]; end
  always @(posedge SPILoad) if(aresetn) frames = frames + 1;

  integer errors = 0;
  reg ok;
  reg [31:0] d;

`include "tb_helpers.vh"

  task wait_idle;
    integer t;
    begin
      t = 0;
      d = 1;
      repeat(20) @(posedge aclk);             // busy bit asserts a few clocks after the B handshake
      while(d[0] && t < 50) begin bfm.read(16'h0008, d, ok); t = t + 1; end
      if(d[0]) begin $display("ERROR: SPI never went idle"); errors = errors + 1; end
    end
  endtask

  initial
  begin
    repeat(10) @(posedge aclk);
    aresetn = 1;
    repeat(10) @(posedge aclk);

    // 1. normal write/shift
    bfm.write(16'h0000, 32'h00001234, ok);
    check_eq("write 0x0 ok", ok, 1);
    wait_idle;
    check_eq("frames after 0x0 write", frames, 1);
    check_eq("MOSI word", mosi_word, 16'h1234);
    bfm.read(16'h0004, d, ok);
    check_eq("MISO word", d, 16'hA5C3);
    bfm.read(16'h0000, d, ok);
    check_eq("readback reg 0", d, 32'h1234);

    // 2. writes to read-only / unused offsets must complete and not start a shift
    bfm.write(16'h0004, 32'hDEAD0004, ok);
    check_eq("write 0x4 completes", ok, 1);
    bfm.write(16'h000C, 32'hDEAD000C, ok);
    check_eq("write 0xC completes", ok, 1);
    bfm.write(16'h0008, 32'h0000BEEF, ok);
    check_eq("write 0x8 completes", ok, 1);
    repeat(200) @(posedge aclk);
    check_eq("no frames from 0x4/0x8/0xC", frames, 1);
    bfm.read(16'h0000, d, ok);
    check_eq("reg 0 unchanged", d, 32'h1234);

    // 3. bus still usable afterwards
    bfm.write(16'h0000, 32'h00005A5A, ok);
    check_eq("write 0x0 after stray writes", ok, 1);
    wait_idle;
    check_eq("frames after 2nd write", frames, 2);
    check_eq("MOSI word 2", mosi_word, 16'h5A5A);

    // 4. back to back writes stall correctly and both are shifted
    bfm.write(16'h0000, 32'h00000F0F, ok);
    bfm.write(16'h0000, 32'h0000F0F0, ok);
    wait_idle;
    check_eq("frames after back to back", frames, 4);
    check_eq("MOSI word 4", mosi_word, 16'hF0F0);

    // 5. read with RREADY back-pressure
    bfm.rready_delay = 5;
    bfm.read(16'h0000, d, ok);
    check_eq("readback with backpressure", d, 32'hF0F0);
    bfm.read(16'h0004, d, ok);
    bfm.rready_delay = 0;

    finish_test(bfm.error_count + chk.error_count);
  end

  initial begin #5_000_000; $display("ERROR: global timeout"); $display("TEST FAIL"); $finish; end

endmodule
