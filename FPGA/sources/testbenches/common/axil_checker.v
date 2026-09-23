`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Design Name:    Saturn unit test infrastructure
// Module Name:    axil_checker
// Description:    passive AXI4-Lite slave protocol checker. Counts violations of:
//                 - RDATA/RRESP change while RVALID && !RREADY
//                 - RVALID dropped without handshake
//                 - BVALID dropped without handshake
//                 - AWREADY/WREADY/ARREADY or response channels X after reset
//////////////////////////////////////////////////////////////////////////////////

module axil_checker #
(
  parameter integer DATA_WIDTH = 32,
  parameter NAME = "axil"
)
(
  input wire                  aclk,
  input wire                  aresetn,
  input wire                  awready,
  input wire                  wready,
  input wire                  bvalid,
  input wire                  bready,
  input wire                  arready,
  input wire [DATA_WIDTH-1:0] rdata,
  input wire [1:0]            rresp,
  input wire                  rvalid,
  input wire                  rready
);

  integer error_count = 0;
  reg                  prev_rvalid = 0, prev_rready = 0, prev_bvalid = 0, prev_bready = 0;
  reg [DATA_WIDTH-1:0] prev_rdata = 0;
  reg [1:0]            prev_rresp = 0;

  always @(posedge aclk)
  begin
    if(aresetn)
    begin
      if(prev_rvalid && !prev_rready)
      begin
        if(!rvalid)
        begin
          if(error_count < 10) $display("%0t %s CHECK ERROR: RVALID dropped without handshake", $time, NAME);
          error_count = error_count + 1;
        end
        else if(rdata !== prev_rdata || rresp !== prev_rresp)
        begin
          if(error_count < 10) $display("%0t %s CHECK ERROR: RDATA changed while RVALID && !RREADY (0x%0h -> 0x%0h)",
                   $time, NAME, prev_rdata, rdata);
          error_count = error_count + 1;
        end
      end
      if(prev_bvalid && !prev_bready && !bvalid)
      begin
        if(error_count < 10) $display("%0t %s CHECK ERROR: BVALID dropped without handshake", $time, NAME);
        error_count = error_count + 1;
      end
      if(^{awready, wready, arready, rvalid, bvalid} === 1'bx)
      begin
        if(error_count < 10) $display("%0t %s CHECK ERROR: X on handshake outputs", $time, NAME);
        error_count = error_count + 1;
      end
    end
    prev_rvalid <= rvalid;
    prev_rready <= rready;
    prev_rdata  <= rdata;
    prev_rresp  <= rresp;
    prev_bvalid <= bvalid;
    prev_bready <= bready;
  end

endmodule
