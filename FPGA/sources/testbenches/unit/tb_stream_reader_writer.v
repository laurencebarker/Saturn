`timescale 1ns / 1ps
// SOURCES: stream_reader_writer.v
//////////////////////////////////////////////////////////////////////////////////
// Module Name:    tb_stream_reader_writer
// Description:    self checking test of AXI_Stream_Reader_Writer (DMA <-> stream)
//                 write side: AXI4 bursts from a master that sends W data of the next
//                 burst before taking the B response of the previous one (legal AXI).
//                 every burst must get exactly one B response and every beat must
//                 appear on the output stream, in order.
//                 read side: bursts read stream data in order with correct RLAST.
//////////////////////////////////////////////////////////////////////////////////

module tb_stream_reader_writer;

  reg aclk = 0;
  reg aresetn = 0;
  always #4 aclk = ~aclk;

  // AXI4 write channels
  reg  [15:0] awaddr = 0; reg awvalid = 0; wire awready; reg [7:0] awid = 0, awlen = 0;
  reg  [31:0] wdata = 0;  reg wvalid = 0;  wire wready;  reg wlast = 0;
  wire [1:0]  bresp;      wire bvalid;     reg bready = 0;
  // AXI4 read channels
  reg  [15:0] araddr = 0; reg arvalid = 0; wire arready; reg [7:0] arid = 0, arlen = 0;
  wire [31:0] rdata; wire [1:0] rresp; wire [7:0] rid; wire rlast, rvalid; reg rready = 0;
  // streams
  wire [31:0] m_tdata; wire m_tvalid; reg m_tready = 1;
  reg  [31:0] s_tdata = 0; reg s_tvalid = 1; wire s_tready;
  wire activity;

  AXI_Stream_Reader_Writer #(.AXI_DATA_WIDTH(32), .AXI_ADDR_WIDTH(16), .AXI_ID_WIDTH(8)) dut (
    .aclk(aclk), .aresetn(aresetn),
    .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready), .s_axi_awid(awid),
    .s_axi_awlen(awlen), .s_axi_awsize(3'd2), .s_axi_awburst(2'd1),
    .s_axi_wdata(wdata), .s_axi_wvalid(wvalid), .s_axi_wready(wready), .s_axi_wstrb(4'hF), .s_axi_wlast(wlast),
    .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
    .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready), .s_axi_arid(arid),
    .s_axi_arlen(arlen), .s_axi_arsize(3'd2), .s_axi_arburst(2'd1),
    .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rid(rid), .s_axi_rlast(rlast),
    .s_axi_rvalid(rvalid), .s_axi_rready(rready),
    .m_axis_tdata(m_tdata), .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready),
    .s_axis_tready(s_tready), .s_axis_tdata(s_tdata), .s_axis_tvalid(s_tvalid),
    .Activity(activity));

  axis_checker #(.DATA_WIDTH(32), .NAME("m_axis")) chk (.aclk(aclk), .aresetn(aresetn),
    .tdata(m_tdata), .tvalid(m_tvalid), .tready(m_tready));

  integer errors = 0;
`include "tb_helpers.vh"

  // output stream scoreboard: data must be 0,1,2,...
  integer next_out = 0;
  reg random_tready = 0;
  always @(posedge aclk)
  begin
    if(random_tready) m_tready <= $random;
    if(m_tvalid && m_tready)
    begin
      if(m_tdata !== next_out) begin if(errors < 10) $display("%0t ERROR: stream got %0d expected %0d", $time, m_tdata, next_out); errors = errors + 1; end
      next_out = next_out + 1;
    end
  end

  // B response counter; BREADY delayed
  integer bcount = 0;
  integer bdelay = 0;
  always @(posedge aclk)
  begin
    if(bvalid && bready) bcount = bcount + 1;
  end
  initial forever begin
    @(posedge aclk);
    if(bvalid && !bready) begin repeat(bdelay) @(posedge aclk); #1 bready = 1; @(posedge aclk); #1 bready = 0; end
  end

  // write data channel process: sends all beats of all bursts back to back
  // (independent of AW and B, so W of burst N+1 can precede B of burst N)
  integer nbursts, beat, b, total_beats;
  integer lens [0:63];
  initial
  begin : wproc
    wait(aresetn);
    repeat(5) @(posedge aclk);
    wait(nbursts > 0);
    for(b = 0; b < nbursts; b = b + 1)
      for(beat = 0; beat <= lens[b]; beat = beat + 1)
      begin
        #1 wvalid = 1; wdata = total_beats; wlast = (beat == lens[b]);
        @(posedge aclk);
        while(!wready) @(posedge aclk);
        total_beats = total_beats + 1;
        #1 wvalid = 0; wlast = 0;
      end
  end

  // address channel process: AW for each burst, slightly behind
  integer ab;
  initial
  begin : awproc
    wait(aresetn);
    repeat(5) @(posedge aclk);
    wait(nbursts > 0);
    for(ab = 0; ab < nbursts; ab = ab + 1)
    begin
      repeat(3) @(posedge aclk);
      #1 awvalid = 1; awlen = lens[ab]; awid = ab;
      @(posedge aclk);
      while(!awready) @(posedge aclk);
      #1 awvalid = 0;
    end
  end

  // read side: one burst of 4 beats
  integer rb, rexp;
  initial
  begin
    nbursts = 0; total_beats = 0;
    for(b = 0; b < 64; b = b + 1) lens[b] = (b % 3 == 0) ? 0 : (b % 3);   // mix of 1,2,3 beat bursts
    repeat(5) @(posedge aclk);
    aresetn = 1;
    random_tready = 1;
    bdelay = 6;
    nbursts = 40;
    rb = 0;
    while((bcount < nbursts) && rb < 20000) begin @(posedge aclk); rb = rb + 1; end
    repeat(50) @(posedge aclk);
    check_eq("one B response per burst", bcount, nbursts);
    check_eq("all beats on output stream", next_out, total_beats);

    // read burst of 4 beats from an incrementing stream source
    #1 araddr = 0; arlen = 3; arid = 8'h5A; arvalid = 1;
    @(posedge aclk); while(!arready) @(posedge aclk);
    #1 arvalid = 0;
    rexp = s_tdata;
    for(rb = 0; rb < 4; rb = rb + 1)
    begin
      while(!rvalid) @(posedge aclk);
      #1 rready = 1;
      @(posedge aclk);
      check_eq("read data", rdata, rexp);
      check_eq("read id", rid, 8'h5A);
      check_eq("rlast", rlast, (rb == 3));
      rexp = rexp + 1;
      #1 rready = 0;
    end

    finish_test(chk.error_count);
  end
  always @(posedge aclk) if(s_tvalid && s_tready) s_tdata <= s_tdata + 1;

  initial begin #2_000_000; $display("ERROR: global timeout"); $display("TEST FAIL"); $finish; end
endmodule
