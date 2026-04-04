`timescale 1ns / 100ps

module binary_neuron_p_tb #(
  parameter int NUM_TESTS = 10000,
  parameter int P_W = 8,
  parameter int MAX_LENGTH = 1,
  parameter int MAX_SUM = MAX_LENGTH * P_W,
  parameter int MIN_CYCLES_BETWEEN_TESTS = 1,
  parameter int MAX_CYCLES_BETWEEN_TESTS = 10,
  parameter int MIN_CYCLES_BETWEEN_VALID_IN = 1,
  parameter int MAX_CYCLES_BETWEEN_VALID_IN = 10,
  parameter bit LOG_INPUTS = 1'b1,
  parameter bit LOG_OUTPUTS = 1'b1
);
  
  // LOCALPARAMS
  localparam int TOTAL_LATENCY = $clog2(P_W) + 2;
  localparam int POPCOUNT_LATENCY = $clog2(P_W);
  localparam int THRESHOLD_R_DELAY = POPCOUNT_LATENCY;
  localparam int LAST_DELAY = 1 + POPCOUNT_LATENCY;
  localparam int VALID_IN_DELAY = 1 + POPCOUNT_LATENCY;
  localparam int MAX_PC_WIDTH = $clog2(MAX_SUM + 1);

  // DUT HOOKUPS
  logic                    clk;
  logic                    rst;
  logic                    en;

  logic [P_W-1:0]          x;
  logic [P_W-1:0]          w;
 
  logic [MAX_PC_WIDTH-1:0] threshold;
  
  logic                    valid_in;
  logic                    last;
  logic                    valid_out;
  logic                    y;
  logic [MAX_PC_WIDTH-1:0] popcount;

  // INSTANTIATE DUT
  binary_neuron_p #(
      .P_W(P_W),
      .MAX_PC_WIDTH(MAX_PC_WIDTH)
  ) DUT (
      .clk(clk),
      .rst(rst),
      .en(en),
      .x(x),
      .w(w),
      .threshold(threshold),
      .valid_in(valid_in),
      .last(last),
      .valid_out(valid_out),
      .y(y),
      .popcount(popcount)
  );

  // CLASS DEF
  class np_item;
 
    rand int length;
    rand bit [P_W-1:0] x[];
    rand bit [P_W-1:0] w[];

    rand bit [MAX_PC_WIDTH-1:0] threshold;

    constraint c_len {
      length inside {[1:MAX_LENGTH]};
      x.size() == length;
      w.size() == length;
    }

    constraint c_thresh {
      threshold inside {[0:length * P_W]};
    }

  endclass

  typedef struct {
    int popcount;
    logic y;
  } dut_t;

  // COVERAGE



  // FUNCTIONAL MODEL
  //// POPCOUNT
  function int compute_popcount (input logic [P_W-1:0] x, input logic [P_W-1:0] w);
    automatic logic [P_W-1:0] xnor_result = ~(x^w);
    automatic int sum = 0;

    for (int i=0; i<P_W; i++) begin
      sum = sum + xnor_result[i];
    end


    return sum;

  endfunction

  //// PIPELINE OUTPUT
  function void compute_results(input np_item item, output int popcount, output logic y);
    popcount = 0;
    y = 1'b0;
    for (int i=0; i<item.length; i++) begin
      popcount += compute_popcount(item.x[i], item.w[i]);
    end

    y = (popcount >= item.threshold);
  endfunction

  // GLOBAL VARS
  int passed;
  int failed;
  int num_tests;

  // MAILBOXES
  mailbox scoreboard_input_mailbox = new;
  mailbox scoreboard_result_mailbox = new;
  mailbox driver_mailbox = new;

  // CLOCK
  initial begin : gen_clk
    clk = 1'b0;
    forever #5 clk = ~clk;
  end


  // INIT DUT
  initial begin : init_dut
    $timeformat(-9, 0, " ns");

    $display("[%0t] INITIALIZING DUT...", $time);
    rst <= 1'b1;
    valid_in <= 1'b0;
    x <= '0;
    w <= '0;
    en <='0;
    last <= 1'b0;
    threshold <= '0;
    repeat (5) @(posedge clk);
    @(negedge clk);
    en <= 1'b1;
    rst <= 1'b0;
    $display("[%0t] INITIALIZION COMPLETE...", $time);

  end


  // GENERATE
  initial begin : generator
    np_item test;

    for (int i=0; i<NUM_TESTS; i++) begin
      test = new();
      assert (test.randomize())
      else $fatal(1, "FAILED TO RANDOMIZE!");
      
      driver_mailbox.put(test);
    end
  end

  // DRIVER
  initial begin : driver 
    np_item item;

    @(posedge clk iff !rst);
    
    forever begin
      driver_mailbox.get(item);
      scoreboard_input_mailbox.put(item);

      $display("[%0t] TEST %d", $time, ++num_tests);
      for (int i=0; i<item.length-1; i++) begin
        repeat ($urandom_range(MIN_CYCLES_BETWEEN_VALID_IN - 1, MAX_CYCLES_BETWEEN_VALID_IN - 1)) @(posedge clk); 
        x <= item.x[i];
	w <= item.w[i];
	valid_in <= 1'b1;
	last <= 0;
        @(posedge clk);
	if (LOG_INPUTS) $display("[%0t] X= %b, W= %b, VALID_IN= %b\n LAST= 0", $time, item.x[i], item.w[i], 1'b1);
      end
      
      repeat ($urandom_range(MIN_CYCLES_BETWEEN_VALID_IN - 1, MAX_CYCLES_BETWEEN_VALID_IN - 1)) @(posedge clk); 
      x <= item.x[item.length-1];
      w <= item.w[item.length-1];
      valid_in <= 1'b1;
      threshold <= item.threshold;
      last <= 1'b1;
      if (LOG_INPUTS) $display("[%0t] X= %b, W= %b, VALID_IN= %b\n LAST= 1, THRESHOLD= %d", $time, item.x[item.length-1], item.w[item.length-1], 1'b1, item.threshold);
      @(posedge clk);
      valid_in <= 1'b0;
      last <= 1'b0;
       
      repeat ($urandom_range(MIN_CYCLES_BETWEEN_TESTS - 1, MAX_CYCLES_BETWEEN_TESTS - 1)) @(posedge clk); 
    end    
  end

  // DONE MONITOR 
  initial begin : done_monitor
    dut_t result;
    forever begin	
      @(posedge clk iff valid_out);
      result.popcount = popcount;
      result.y = y;
      if (LOG_OUTPUTS) $display("[%0t] POPCOUNT= %d, Y= %b", $time, popcount, y);
      scoreboard_result_mailbox.put(result);

    end
  end

  // SCOREBOARD
  initial begin : scoreboard
    dut_t expected_result;
    dut_t actual_result;

    np_item test_input;

    passed = 0;
    failed = 0;

    for (int i=0; i<NUM_TESTS; i++) begin
      test_input = new();
      scoreboard_input_mailbox.get(test_input);
      scoreboard_result_mailbox.get(actual_result);

      compute_results(test_input, expected_result.popcount, expected_result.y);

      if (expected_result.popcount == actual_result.popcount) begin
        if (expected_result.y == actual_result.y) begin
          $display("[%0t][PASS] (EXP_PC == ACTUAL_PC) = %d, (EXP_Y == ACTUAL_Y) = %b", $time, actual_result.popcount, actual_result.y);
          passed++;
        end else begin 
	  $display("[%0t][FAIL] EXP_PC= %d, ACTUAL_PC= %d, EXP_Y= %b, ACTUAL_Y= %b", $time, expected_result.popcount, actual_result.popcount, expected_result.y, actual_result.y);
          failed++;
	end

      end else begin 
	  $display("[%0t][FAIL] EXP_PC= %d, ACTUAL_PC= %d, EXP_Y= %b, ACTUAL_Y= %b", $time, expected_result.popcount, actual_result.popcount, expected_result.y, actual_result.y);
	  failed++;
      end
    end
    $display("=========================RESULTS============================");
    $display("TESTS COMPLETED: %0d PASSED, %0d FAILED", passed, failed);
    $display(" "); 
    $display("============================================================");

    disable gen_clk;
  end

  // ASSERTIONS
  last_with_valid_in : assert property (@(posedge clk) disable iff (rst) ($rose(last) |-> $rose(valid_in))) else $error("[%0t] ASSERT: LAST INPUTTED WITHOUT VALID_IN", $time);
  threshold_on_last : assert property (@(posedge clk) disable iff (rst) $changed(threshold) |-> $rose(last)) else $error("[%0t] ASSERT: THRESHOLD INPUTTED WITHOUT LAST", $time);
  stable_low_en : assert property (@(posedge clk) disable iff (rst) !en |=> $stable(y) && $stable(popcount) && $stable(valid_out)) else $error("[%0t] ASSERT: VALUES CHANGE WHEN !EN", $time);
  last_to_valid_out_latency : assert property (@(posedge clk) disable iff (rst) en [-> TOTAL_LATENCY] |=> valid_out == $past(last, TOTAL_LATENCY, en)) else $error("[%0t] ASSERT: LATENCY FROM LAST TO VALID_OUT INCORRECT", $time);

endmodule

