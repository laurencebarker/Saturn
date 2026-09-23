`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Design Name:    Saturn unit test infrastructure
// Module Name:    axis_checker
// Description:    passive AXI4-Stream master protocol checker and beat counter.
//                 - TDATA must not change while TVALID && !TREADY
//                 - TVALID must not drop without a handshake
//                 beat_count counts completed transfers.
//////////////////////////////////////////////////////////////////////////////////

module axis_checker #
(
  parameter integer DATA_WIDTH = 32,
  parameter NAME = "axis"
)
(
  input wire                  aclk,
  input wire                  aresetn,
  input wire [DATA_WIDTH-1:0] tdata,
  input wire                  tvalid,
  input wire                  tready
);

  integer error_count = 0;
  integer beat_count = 0;
  reg                  prev_tvalid = 0, prev_tready = 0;
  reg [DATA_WIDTH-1:0] prev_tdata = 0;

  always @(posedge aclk)
  begin
    if(aresetn)
    begin
      if(prev_tvalid && !prev_tready)
      begin
        if(!tvalid)
        begin
          if(error_count < 10) $display("%0t %s CHECK ERROR: TVALID dropped without handshake", $time, NAME);
          error_count = error_count + 1;
        end
        else if(tdata !== prev_tdata)
        begin
          if(error_count < 10) $display("%0t %s CHECK ERROR: TDATA changed while TVALID && !TREADY", $time, NAME);
          error_count = error_count + 1;
        end
      end
      if(tvalid && tready)
        beat_count = beat_count + 1;
    end
    prev_tvalid <= tvalid;
    prev_tready <= tready;
    prev_tdata  <= tdata;
  end

endmodule
