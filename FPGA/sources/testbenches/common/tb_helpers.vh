//////////////////////////////////////////////////////////////////////////////////
// common helpers for self checking unit tests; `include inside the tb module.
// requires the tb to declare: integer errors;
//////////////////////////////////////////////////////////////////////////////////
  task check_eq;
    input [8*64-1:0] what;
    input [63:0]  got, exp;
    begin
      if(got !== exp)
      begin
        $display("%0t ERROR: %0s got 0x%0h expected 0x%0h", $time, what, got, exp);
        errors = errors + 1;
      end
    end
  endtask

  task check_true;
    input [8*64-1:0] what;
    input         cond;
    begin
      if(cond !== 1'b1)
      begin
        $display("%0t ERROR: %0s", $time, what);
        errors = errors + 1;
      end
    end
  endtask

  task finish_test;
    input integer extra_errors;
    begin
      errors = errors + extra_errors;
      if(errors == 0) $display("TEST PASS");
      else            $display("TEST FAIL: %0d errors", errors);
      $finish;
    end
  endtask
