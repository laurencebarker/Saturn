// Push Button debounce routine
// Found on the Internet, author unknown
// used to debounce a switch or push button.
// Input is pb and outout clean_pb.
// Button must be stable for debounce time before state changes,
// debounce time is dependent on clk and counter_bits

// eg with clock = 10MHz and debounce_count = 10000 stable time is 

//  0.1us * 10000 = 1mS

//  Phil Harman VK6APH 15th February 2006
// modified Laurence Barker G8NJJ to make the time clearer
// and to add "clock enable" input

module debounce(aclk, ce_n, pb_in, clean_pb, clean_pbn);
	
    output reg clean_pb = 0;    // debounced output
    output reg clean_pbn = 1;    // debounced output, inverted
    input wire pb_in;           // bouncy, asynchronous input	
(* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK" *)
    input wire aclk;             // clock signal
    input wire ce_n;            // active low clock enable
	
parameter debounce_count = 1024;
localparam NumBits = clogb2 (debounce_count -1); // 0 to (Divisor -1)

reg [NumBits-1:0] count;
reg [3:0] pb_history = 0;

always @ (posedge aclk)
if(!ce_n)
begin
	pb_history <= {pb_history[2:0], pb_in};
	
	if (pb_history[3] != pb_history[2])
		count <= debounce_count-1;
	else if(count == 0)
	begin
		clean_pb <= pb_history[3];
		clean_pbn <= !pb_history[3];
	end
	else
		count <= count - 1'b1;
end 


//
// function to find length required for count register
//
function integer clogb2;
input [31:0] depth;
begin
  for(clogb2=0; depth>0; clogb2=clogb2+1)
  depth = depth >> 1;
end
endfunction


endmodule