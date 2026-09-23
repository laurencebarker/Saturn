`timescale 1ns / 1ps
// SOURCES: axi_spi_adc.v
//////////////////////////////////////////////////////////////////////////////////
// Module Name:    tb_axi_spi_adc
// Description:    test of the AXI side of AXI_SPI_ADC (ADC78H90 poller)
//                 - SPI outputs have defined values from reset
//                 - reads of all 7 channels complete, RDATA stable under back-pressure
//                 - a stray write completes instead of stalling the bus
//                 the ADC itself is modelled only as a constant MISO level
//////////////////////////////////////////////////////////////////////////////////

module tb_axi_spi_adc;

  reg aclk = 0;
  reg aresetn = 0;
  always #4 aclk = ~aclk;

`include "axil_tb_bus.vh"

  wire nCS, MOSI, SCLK;
  reg  MISO = 1;
  AXI_SPI_ADC dut (.aclk(aclk), .aresetn(aresetn), .nCS(nCS), .MOSI(MOSI), .MISO(MISO), .SCLK(SCLK),
                   `AXIL_SLAVE_PORTS);

  integer errors = 0;
  reg ok;
  reg [31:0] d;
`include "tb_helpers.vh"

  integer i;
  initial
  begin
    repeat(5) @(posedge aclk);
    check_true("nCS defined during reset", nCS === 1'b1);
    check_true("SCLK defined during reset", SCLK !== 1'bx);
    check_true("MOSI defined during reset", MOSI !== 1'bx);
    aresetn = 1;
    repeat(20000) @(posedge aclk);            // let all channels convert

    bfm.rready_delay = 5;
    for(i = 0; i < 7; i = i + 1)
    begin
      bfm.read(i*4, d, ok);
      check_true("channel read completes", ok);
      check_true("channel value defined", ^d !== 1'bx);
    end
    bfm.rready_delay = 0;

    bfm.write(16'h0000, 32'hFFFFFFFF, ok);
    check_eq("stray write completes", ok, 1);
    bfm.read(16'h0008, d, ok);
    check_true("bus usable after write", ok);

    finish_test(bfm.error_count + chk.error_count);
  end

  initial begin #5_000_000; $display("ERROR: global timeout"); $display("TEST FAIL"); $finish; end
endmodule
