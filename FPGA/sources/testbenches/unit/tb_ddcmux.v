`timescale 1ns / 1ps
// SOURCES: DDCMux.v
//////////////////////////////////////////////////////////////////////////////////
// Module Name:    tb_ddcmux
// Description:    self checking test of AXIS_DDC_Multiplexer
//                 - output frame = config word then samples per DDC rate setting,
//                   including an interleaved DDC pair and disabled (discarded) DDCs
//                 - random output back-pressure; protocol checked
//                 - shutdown must complete even if a DDC stops producing samples
//////////////////////////////////////////////////////////////////////////////////

module tb_ddcmux;

  reg aclk = 0;
  reg aresetn = 0;
  always #4 aclk = ~aclk;

  reg         enabled = 0;
  reg  [31:0] DDCconfig = 0;
  wire [31:0] DDCconfigout;
  wire        active, fiforstn;
  wire [63:0] m_tdata;
  wire        m_tvalid;
  reg         m_tready = 1;
  reg         random_ready = 0;

  // DDC source models: always valid (unless stalled), data = {ddc, count}
  reg  [9:0]  src_stall = 0;
  reg  [31:0] src_count [0:9];
  wire [9:0]  s_tready;
  wire [9:0]  s_tvalid = ~src_stall;
  wire [47:0] s_tdata [0:9];
  genvar g;
  generate for(g = 0; g < 10; g = g + 1) begin : src
    assign s_tdata[g] = {8'hD0 + g[7:0], 8'h00, src_count[g]};
    initial src_count[g] = 0;
    always @(posedge aclk) if(s_tvalid[g] && s_tready[g]) src_count[g] <= src_count[g] + 1;
  end endgenerate

  AXIS_DDC_Multiplexer #(.AXIS_INPUT_SIZE(48)) dut (
    .aclk(aclk), .aresetn(aresetn),
    .s00_axis_tdata(s_tdata[0]), .s00_axis_tvalid(s_tvalid[0]), .s00_axis_tready(s_tready[0]),
    .s01_axis_tdata(s_tdata[1]), .s01_axis_tvalid(s_tvalid[1]), .s01_axis_tready(s_tready[1]),
    .s02_axis_tdata(s_tdata[2]), .s02_axis_tvalid(s_tvalid[2]), .s02_axis_tready(s_tready[2]),
    .s03_axis_tdata(s_tdata[3]), .s03_axis_tvalid(s_tvalid[3]), .s03_axis_tready(s_tready[3]),
    .s04_axis_tdata(s_tdata[4]), .s04_axis_tvalid(s_tvalid[4]), .s04_axis_tready(s_tready[4]),
    .s05_axis_tdata(s_tdata[5]), .s05_axis_tvalid(s_tvalid[5]), .s05_axis_tready(s_tready[5]),
    .s06_axis_tdata(s_tdata[6]), .s06_axis_tvalid(s_tvalid[6]), .s06_axis_tready(s_tready[6]),
    .s07_axis_tdata(s_tdata[7]), .s07_axis_tvalid(s_tvalid[7]), .s07_axis_tready(s_tready[7]),
    .s08_axis_tdata(s_tdata[8]), .s08_axis_tvalid(s_tvalid[8]), .s08_axis_tready(s_tready[8]),
    .s09_axis_tdata(s_tdata[9]), .s09_axis_tvalid(s_tvalid[9]), .s09_axis_tready(s_tready[9]),
    .m_axis_tdata(m_tdata), .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready),
    .enabled(enabled), .DDCconfig(DDCconfig), .DDCconfigout(DDCconfigout),
    .active(active), .fiforstn(fiforstn));

  axis_checker #(.DATA_WIDTH(64), .NAME("m_axis")) chk (.aclk(aclk), .aresetn(aresetn),
    .tdata(m_tdata), .tvalid(m_tvalid), .tready(m_tready));

  integer errors = 0;
`include "tb_helpers.vh"

  // expected output: build one frame's sequence of (ddc) tags from the config
  reg [7:0] exp_tag [0:255];
  integer   exp_len;
  task build_frame;
    input [31:0] cfg;
    integer n, k, cnt;
    reg [2:0] r;
    begin
      exp_len = 0;
      exp_tag[exp_len] = 8'h80; exp_len = exp_len + 1;      // config word marker
      n = 0;
      while(n < 10)
      begin
        r = (cfg >> (3*n)) & 7;
        if(r == 3'b111 && n[0] == 0)
        begin
          r = (cfg >> (3*(n+1))) & 7;
          cnt = (r <= 1) ? 1 : (1 << (r-1));
          if(r == 7) cnt = 32;
          for(k = 0; k < cnt; k = k + 1)
          begin
            exp_tag[exp_len] = 8'hD0 + n;   exp_len = exp_len + 1;
            exp_tag[exp_len] = 8'hD0 + n+1; exp_len = exp_len + 1;
          end
          n = n + 2;
        end
        else
        begin
          cnt = (r <= 1) ? 1 : (1 << (r-1));
          if(r == 7) cnt = 32;
          if(r != 0)
            for(k = 0; k < cnt; k = k + 1) begin exp_tag[exp_len] = 8'hD0 + n; exp_len = exp_len + 1; end
          n = n + 1;
        end
      end
    end
  endtask

  // output monitor: compare against the repeating expected frame
  integer pos = 0, words = 0, frames_seen = 0;
  reg     checking = 0;
  always @(posedge aclk)
  begin
    if(random_ready) m_tready <= $random;
    if(m_tvalid && m_tready && checking)
    begin
      words = words + 1;
      if(exp_tag[pos] == 8'h80)
      begin
        if(m_tdata[63:48] !== 16'h8000 || m_tdata[31:0] !== DDCconfig)
        begin $display("%0t ERROR: bad config word 0x%0h", $time, m_tdata); errors = errors + 1; end
        frames_seen = frames_seen + 1;
      end
      else if(m_tdata[47:40] !== exp_tag[pos] || m_tdata[63:48] !== 0)
      begin
        if(errors < 10) $display("%0t ERROR: word %0d got tag 0x%0h expected 0x%0h", $time, pos, m_tdata[47:40], exp_tag[pos]);
        errors = errors + 1;
      end
      pos = (pos + 1) % exp_len;
    end
  end

  integer t;
  initial
  begin
    repeat(5) @(posedge aclk);
    aresetn = 1;
    repeat(5) @(posedge aclk);

    // DDC0 48k, DDC1 96k, DDC2/3 interleaved at 192k, DDC4 384k, DDC5..9 disabled
    DDCconfig = {2'b00, 3'd0, 3'd0, 3'd0, 3'd0, 3'd0, 3'd4, 3'd3, 3'b111, 3'd2, 3'd1};
    build_frame(DDCconfig);
    checking = 1;
    random_ready = 1;
    enabled = 1;
    t = 0;
    while(frames_seen < 20 && t < 200000) begin @(posedge aclk); t = t + 1; end
    check_true("20 frames produced", frames_seen >= 20);
    check_eq("DDCconfigout follows config", DDCconfigout, DDCconfig);

    // clean shutdown
    enabled = 0;
    t = 0;
    while(active && t < 10000) begin @(posedge aclk); t = t + 1; end
    check_eq("inactive after disable", active, 0);
    repeat(20) @(posedge aclk);
    random_ready = 0; m_tready = 1;

    // restart, then a disabled DDC stops producing samples: shutdown must still complete
    checking = 0;
    enabled = 1;
    repeat(500) @(posedge aclk);
    src_stall[7] = 1;
    repeat(2000) @(posedge aclk);
    enabled = 0;
    t = 0;
    while(active && t < 200000) begin @(posedge aclk); t = t + 1; end
    check_eq("shutdown completes with stalled DDC", active, 0);

    // after the DDC recovers, a new enable must reset the input FIFOs and run again
    src_stall[7] = 0;
    repeat(20) @(posedge aclk);
    enabled = 1;
    t = 0;
    while(fiforstn && t < 1000) begin @(posedge aclk); t = t + 1; end
    check_eq("fifo reset pulsed on re-enable", fiforstn, 0);

    finish_test(chk.error_count);
  end

  initial begin #20_000_000; $display("ERROR: global timeout"); $display("TEST FAIL"); $finish; end
endmodule
