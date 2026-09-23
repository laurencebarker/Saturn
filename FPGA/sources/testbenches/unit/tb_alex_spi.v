`timescale 1ns / 1ps
// SOURCES: AXILite_Alex_SPI.v
//////////////////////////////////////////////////////////////////////////////////
// Module Name:    tb_alex_spi
// Description:    self checking test of AXILite_Alex_SPI
//                 - a TX word write produces exactly one 16 bit TX frame, even if
//                   the unused bits 31:16 are written non zero
//                 - an RX word write produces one 32 bit RX frame
//                 - bit 11 of the TX frame follows TX_Strobe; TX ant word used when TX
//                 - SPI clock during reset runs at the normal divided rate
//////////////////////////////////////////////////////////////////////////////////

module tb_alex_spi;

  reg aclk = 0;
  reg aresetn = 0;                           // prev_aresetn powers up 1, so this is a reset falling edge
  always #4 aclk = ~aclk;

`include "axil_tb_bus.vh"

  wire SPI_data, SPI_ck, Rx_load_strobe, Tx_load_strobe;
  reg  TX_Strobe = 0;

  AXILite_Alex_SPI #(.CLOCK_DIVIDER(12)) dut (.aclk(aclk), .aresetn(aresetn),
    .SPI_data(SPI_data), .SPI_ck(SPI_ck), .Rx_load_strobe(Rx_load_strobe),
    .Tx_load_strobe(Tx_load_strobe), .TX_Strobe(TX_Strobe), `AXIL_SLAVE_PORTS);

  integer errors = 0;
  reg ok;
  reg [31:0] d;
`include "tb_helpers.vh"

  // shift register model
  reg [31:0] sr = 0;
  reg [31:0] last_tx = 0, last_rx = 0;
  integer    bits = 0, tx_frames = 0, rx_frames = 0, tx_bits = 0, rx_bits = 0;
  always @(posedge SPI_ck) begin sr = {sr[30:0], SPI_data}; bits = bits + 1; end
  always @(posedge Tx_load_strobe) begin last_tx = sr; tx_bits = bits; bits = 0; tx_frames = tx_frames + 1; end
  always @(posedge Rx_load_strobe) begin last_rx = sr; rx_bits = bits; bits = 0; rx_frames = rx_frames + 1; end

  // minimum SPI clock high/low time, measured in aclk cycles
  integer ck_cycles = 0, min_ck_cycles = 1000;
  reg prev_ck = 0;
  always @(posedge aclk)
  begin
    if(SPI_ck != prev_ck)
    begin
      if(ck_cycles < min_ck_cycles && $time > 0) min_ck_cycles = ck_cycles;
      ck_cycles = 1;
    end
    else ck_cycles = ck_cycles + 1;
    prev_ck = SPI_ck;
  end

  task wait_frames;
    input integer ntx, nrx;
    integer t;
    begin
      t = 0;
      while((tx_frames < ntx || rx_frames < nrx) && t < 20000) begin @(posedge aclk); t = t + 1; end
      repeat(3000) @(posedge aclk);            // and allow any unwanted extra frames to appear
    end
  endtask

  initial
  begin
    repeat(20) @(posedge aclk);                // reset falling edge forces a shift of zeros
    aresetn = 1;
    wait_frames(1, 1);
    check_eq("reset: one TX frame", tx_frames, 1);
    check_eq("reset: one RX frame", rx_frames, 1);
    check_true("SPI clock never faster than divided rate", min_ck_cycles >= 12);

    // 1. TX word, RX ant version, with junk in bits 31:16
    tx_frames = 0; rx_frames = 0;
    bfm.write(16'h0000, 32'hABCD_1234, ok);
    wait_frames(1, 0);
    check_eq("TX frames after one write", tx_frames, 1);
    check_eq("TX frame bits", tx_bits, 16);
    check_eq("TX frame data (bit 11 = strobe = 0)", last_tx[15:0], 16'h1234 & ~16'h0800);
    check_eq("no RX frame", rx_frames, 0);

    // 2. RX word
    tx_frames = 0; rx_frames = 0;
    bfm.write(16'h0004, 32'h8765_4321, ok);
    wait_frames(0, 1);
    check_eq("RX frames", rx_frames, 1);
    check_eq("RX frame bits", rx_bits, 32);
    check_eq("RX frame data", last_rx, 32'h8765_4321);
    check_eq("no TX frame", tx_frames, 0);

    // 3. TX ant word used while transmitting; strobe inserted as bit 11
    tx_frames = 0;
    bfm.write(16'h0008, 32'h0000_0100, ok);
    wait_frames(0, 0);
    tx_frames = 0;
    TX_Strobe = 1;
    wait_frames(1, 0);
    check_eq("TX frame on strobe", tx_frames, 1);
    check_eq("TX ant data with strobe", last_tx[15:0], 16'h0900);
    TX_Strobe = 0;
    tx_frames = 0;
    wait_frames(1, 0);
    check_eq("TX frame on strobe release", tx_frames, 1);
    check_eq("RX ant data restored", last_tx[15:0], 16'h1234 & ~16'h0800);

    finish_test(bfm.error_count + chk.error_count);
  end

  initial begin #20_000_000; $display("ERROR: global timeout"); $display("TEST FAIL"); $finish; end
endmodule
