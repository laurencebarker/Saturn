`timescale 1ns / 1ps
// SOURCES: debounce.v pwm_dac.v
//////////////////////////////////////////////////////////////////////////////////
// Module Name:    tb_debounce_pwm
// Description:    self checking test of debounce and PWM_DAC
//                 debounce: an idle (high) input never reads as pressed from power-up;
//                           a press/release stable for the debounce time is reported;
//                           shorter glitches are ignored
//                 PWM_DAC:  duty cycle 0 -> 0%, 255 -> 100%, 128 -> ~50%
//////////////////////////////////////////////////////////////////////////////////

module tb_debounce_pwm;

  reg aclk = 0;
  always #4 aclk = ~aclk;

  // debounce, clock enable every 4 clocks, count 10
  reg  [1:0] div = 0;
  always @(posedge aclk) div <= div + 1;
  wire ce_n = (div != 0);
  reg  pb_in = 1;                           // idle high (active low key)
  wire clean_pb, clean_pbn;
  debounce #(.debounce_count(10)) db (.aclk(aclk), .ce_n(ce_n), .pb_in(pb_in),
    .clean_pb(clean_pb), .clean_pbn(clean_pbn));

  reg  [7:0] pwm_in = 0;
  wire pwm_out;
  PWM_DAC pwm (.aclk(aclk), .PWM_source(pwm_in), .DAC_bit(pwm_out));

  integer errors = 0;
`include "tb_helpers.vh"

  integer pressed_seen = 0;
  reg     watch_power_up = 1;
  always @(posedge aclk) if(watch_power_up && clean_pbn !== 1'b0) pressed_seen = pressed_seen + 1;

  integer high, i;
  task measure_pwm;
    begin
      repeat(300) @(posedge aclk);
      high = 0;
      for(i = 0; i < 255*4; i = i + 1) begin @(posedge aclk); if(pwm_out) high = high + 1; end
    end
  endtask

  initial
  begin
    repeat(400) @(posedge aclk);
    watch_power_up = 0;
    check_eq("idle key never read as pressed from power-up", pressed_seen, 0);

    pb_in = 0; repeat(20) @(posedge aclk); pb_in = 1;      // 5 enables: glitch
    repeat(100) @(posedge aclk);
    check_eq("short glitch ignored", clean_pbn, 0);
    pb_in = 0; repeat(100) @(posedge aclk);
    check_eq("press reported", clean_pbn, 1);
    check_eq("press reported (true output)", clean_pb, 0);
    pb_in = 1; repeat(100) @(posedge aclk);
    check_eq("release reported", clean_pbn, 0);

    pwm_in = 0;   measure_pwm; check_eq("PWM 0 -> 0%", high, 0);
    pwm_in = 255; measure_pwm; check_eq("PWM 255 -> 100%", high, 255*4);
    pwm_in = 128; measure_pwm; check_eq("PWM 128 -> 128/255", high, 128*4);
    finish_test(0);
  end
endmodule
