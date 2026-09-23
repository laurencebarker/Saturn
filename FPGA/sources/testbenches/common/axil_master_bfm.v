`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Design Name:    Saturn unit test infrastructure
// Module Name:    axil_master_bfm
// Description:    AXI4-Lite master bus functional model for self checking testbenches.
//                 Tasks are called hierarchically, eg: bfm.write(16'h0004, 32'h1234, ok);
//                 Every handshake has a timeout: a slave that never responds makes the
//                 task return ok=0 and increments error_count instead of hanging the sim.
//                 rready_delay / bready_delay hold RREADY / BREADY low for N clocks after
//                 VALID is seen, to exercise slave back-pressure behaviour.
//////////////////////////////////////////////////////////////////////////////////

module axil_master_bfm #
(
  parameter integer ADDR_WIDTH = 16,
  parameter integer DATA_WIDTH = 32,
  parameter integer TIMEOUT = 2000                  // clocks before a handshake is declared hung
)
(
  input  wire                  aclk,
  output reg  [ADDR_WIDTH-1:0] awaddr,
  output reg                   awvalid,
  input  wire                  awready,
  output reg  [DATA_WIDTH-1:0] wdata,
  output reg  [DATA_WIDTH/8-1:0] wstrb,
  output reg                   wvalid,
  input  wire                  wready,
  input  wire [1:0]            bresp,
  input  wire                  bvalid,
  output reg                   bready,
  output reg  [ADDR_WIDTH-1:0] araddr,
  output reg                   arvalid,
  input  wire                  arready,
  input  wire [DATA_WIDTH-1:0] rdata,
  input  wire [1:0]            rresp,
  input  wire                  rvalid,
  output reg                   rready
);

  integer error_count = 0;
  integer rready_delay = 0;
  integer bready_delay = 0;
  reg     verbose = 0;

  initial
  begin
    awaddr = 0; awvalid = 0; wdata = 0; wstrb = {(DATA_WIDTH/8){1'b1}}; wvalid = 0; bready = 0;
    araddr = 0; arvalid = 0; rready = 0;
  end

//
// write: address and data presented together; each channel completes independently
//
  task write;
    input  [ADDR_WIDTH-1:0] addr;
    input  [DATA_WIDTH-1:0] data;
    output                  ok;
    integer t;
    reg aw_done, w_done;
    begin
      write_strb(addr, data, {(DATA_WIDTH/8){1'b1}}, ok);
    end
  endtask

  task write_strb;
    input  [ADDR_WIDTH-1:0]   addr;
    input  [DATA_WIDTH-1:0]   data;
    input  [DATA_WIDTH/8-1:0] strb;
    output                    ok;
    integer t;
    reg aw_done, w_done;
    begin
      ok = 1;
      @(posedge aclk); #1;
      awaddr = addr; awvalid = 1; wdata = data; wstrb = strb; wvalid = 1;
      aw_done = 0; w_done = 0; t = 0;
      while(!(aw_done && w_done) && t < TIMEOUT)
      begin
        @(posedge aclk);
        if(awvalid && awready) aw_done = 1;
        if(wvalid && wready) w_done = 1;
        #1;
        if(aw_done) awvalid = 0;
        if(w_done) wvalid = 0;
        t = t + 1;
      end
      if(!(aw_done && w_done))
      begin
        $display("%0t BFM ERROR: write 0x%0h timeout (aw_done=%0d w_done=%0d)", $time, addr, aw_done, w_done);
        error_count = error_count + 1;
        awvalid = 0; wvalid = 0;
        ok = 0;
      end
      else
      begin
        // response channel
        t = 0;
        while(!bvalid && t < TIMEOUT)
        begin
          @(posedge aclk); #1;
          t = t + 1;
        end
        if(!bvalid)
        begin
          $display("%0t BFM ERROR: write 0x%0h no BVALID", $time, addr);
          error_count = error_count + 1;
          ok = 0;
        end
        else
        begin
          repeat(bready_delay) @(posedge aclk);
          #1 bready = 1;
          @(posedge aclk); #1;
          bready = 0;
          if(verbose) $display("%0t BFM write 0x%0h = 0x%0h", $time, addr, data);
        end
      end
    end
  endtask

//
// read
//
  task read;
    input  [ADDR_WIDTH-1:0] addr;
    output [DATA_WIDTH-1:0] data;
    output                  ok;
    integer t;
    begin
      ok = 1;
      data = 0;
      @(posedge aclk); #1;
      araddr = addr; arvalid = 1; t = 0;
      @(posedge aclk);
      while(!arready && t < TIMEOUT)
      begin
        @(posedge aclk);
        t = t + 1;
      end
      #1 arvalid = 0;
      if(t >= TIMEOUT)
      begin
        $display("%0t BFM ERROR: read 0x%0h no ARREADY", $time, addr);
        error_count = error_count + 1;
        ok = 0;
      end
      else
      begin
        t = 0;
        while(!rvalid && t < TIMEOUT)
        begin
          @(posedge aclk); #1;
          t = t + 1;
        end
        if(!rvalid)
        begin
          $display("%0t BFM ERROR: read 0x%0h no RVALID", $time, addr);
          error_count = error_count + 1;
          ok = 0;
        end
        else
        begin
          repeat(rready_delay) @(posedge aclk);
          #1 rready = 1;
          @(posedge aclk);
          data = rdata;                         // value sampled at the handshake edge
          #1 rready = 0;
          if(verbose) $display("%0t BFM read 0x%0h = 0x%0h", $time, addr, data);
        end
      end
    end
  endtask

endmodule
