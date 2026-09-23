`timescale 1ns / 1ps
// SOURCES: iambic.v
//////////////////////////////////////////////////////////////////////////////////
// Module Name:    tb_iambic
// Description:    self checking test of the iambic keyer
//                 clken is held at 1, so one clock = one 48kHz tick
//                 - dot and dash lengths at standard weight
//                 - dash length correct at maximum weight (255) and 1 WPM (counter width)
//                 - speed 0 (reset value) gives defined output, treated as 1 WPM
//                 - IO8 keys the output in straight/bug mode as well as iambic mode
//////////////////////////////////////////////////////////////////////////////////

module tb_iambic;

  reg clock = 0;
  always #1 clock = ~clock;

  reg  [5:0] cw_speed = 20;
  reg        iambic_mode = 1, keyer_mode = 0, letter_space = 0, paddle_swap = 0;
  reg  [7:0] weight = 50;
  reg        dot_key = 0, dash_key = 0, CWX = 0, IO8 = 0;
  wire       keyer_out;

  iambic #(.clock_speed(48)) dut (.clock(clock), .clken(1'b1), .cw_speed(cw_speed), .iambic(iambic_mode),
    .keyer_mode(keyer_mode), .weight(weight), .letter_space(letter_space), .dot_key(dot_key),
    .dash_key(dash_key), .CWX(CWX), .paddle_swap(paddle_swap), .keyer_out(keyer_out), .IO8(IO8));

  integer errors = 0;
`include "tb_helpers.vh"

  // measure the length of the next key-down element, in clocks
  integer len;
  task measure;
    integer t;
    begin
      t = 0;
      while(keyer_out !== 1'b1 && t < 100000) begin @(posedge clock); t = t + 1; end
      len = 0;
      while(keyer_out === 1'b1 && len < 2000000) begin @(posedge clock); len = len + 1; end
    end
  endtask

  // key a single element: press paddle until output rises, then release
  task one_element;
    input is_dash;
    begin
      if(is_dash) dash_key = 1; else dot_key = 1;
      fork
        measure;
        begin wait(keyer_out === 1'b1); repeat(10) @(posedge clock); dot_key = 0; dash_key = 0; end
      join
      repeat(4000000) begin if(dut.key_state == 0) disable one_element; @(posedge clock); end
    end
  endtask

  function integer near;                // within 3 clocks
    input integer got, exp;
    near = (got >= exp - 3) && (got <= exp + 3);
  endfunction

  initial
  begin
    repeat(10) @(posedge clock);

    // 1. 20 WPM, weight 50: dot 2880 ticks, dash 8640
    one_element(0);
    check_true("dot length at 20 WPM", near(len, 2880));
    one_element(1);
    check_true("dash length at 20 WPM", near(len, 8640));

    // 2. 1 WPM, weight 255: dash = 57600*3*255/50 = 881280 ticks
    cw_speed = 1; weight = 255;
    one_element(1);
    if(!near(len, 881280)) $display("dash length %0d", len);
    check_true("dash length at 1 WPM weight 255", near(len, 881280));

    // 3. speed 0 must behave as 1 WPM (dot = 57600 ticks), never X
    cw_speed = 0; weight = 50;
    one_element(0);
    if(!near(len, 57600)) $display("dot length at speed 0: %0d", len);
    check_true("dot length at speed 0", near(len, 57600));
    check_true("keyer output defined", keyer_out !== 1'bx);

    // 4. IO8 external key in straight mode and in iambic mode
    cw_speed = 20;
    iambic_mode = 0;
    repeat(10) @(posedge clock);
    IO8 = 1; repeat(10) @(posedge clock);
    check_eq("IO8 keys output in straight mode", keyer_out, 1);
    IO8 = 0; repeat(10) @(posedge clock);
    check_eq("IO8 release in straight mode", keyer_out, 0);
    iambic_mode = 1;
    repeat(10) @(posedge clock);
    IO8 = 1; repeat(10) @(posedge clock);
    check_eq("IO8 keys output in iambic mode", keyer_out, 1);
    IO8 = 0; repeat(10) @(posedge clock);
    check_eq("IO8 release in iambic mode", keyer_out, 0);

    finish_test(0);
  end

  initial begin #50_000_000; $display("ERROR: global timeout"); $display("TEST FAIL"); $finish; end
endmodule
