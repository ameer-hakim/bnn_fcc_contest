`timescale 1ns / 10ps

module layer_tb;

  localparam int CLK_PERIOD = 10;  // 10ns = 100MHz
 
  // Start with small topology for easier debugging
  localparam int LAYER_ID = 0;
  localparam int NUM_INPUTS = 8;   
  localparam int NUM_NEURONS = 8;  
  localparam int P_W = 8;          
  localparam int P_N = 4;          
 
  // Calculated values to go with DUT localparams
  localparam int MAX_PC_WIDTH = $clog2(NUM_INPUTS + 1);
  localparam int NEURONS_PER_NP = (NUM_NEURONS / P_N);
  localparam int BEATS_PER_NEURON = (NUM_INPUTS / P_W);
  localparam int WEIGHT_ADDR_WIDTH = $clog2(NEURONS_PER_NP * BEATS_PER_NEURON);
  localparam int THRESHOLD_ADDR_WIDTH = $clog2(NEURONS_PER_NP);

  // DUT hookups
  logic                            clk = 1'b0;
  logic                            rst;
  logic                            config_mode;
  logic                            config_w_we;
  logic                            config_t_we;
  logic [WEIGHT_ADDR_WIDTH-1:0]    config_w_addr;
  logic [THRESHOLD_ADDR_WIDTH-1:0] config_t_addr;
  logic [P_W-1:0]                  config_w_data;
  logic [MAX_PC_WIDTH-1:0]         config_t_data;
  logic [$bits(P_N)-1:0]           config_np_id;
  
  //// DATA
  logic layer_valid_in;
  logic [P_W-1:0] layer_data_in;

  // OUTPUTS
  logic layer_valid_out;
  logic layer_ready;
  logic [P_N-1:0] layer_data_out;
  logic [MAX_PC_WIDTH-1:0] layer_popcounts[P_N];

  // Instantiate DUT
  layer #(
    .NUM_INPUTS(NUM_INPUTS),
    .NUM_NEURONS(NUM_NEURONS),
    .P_W(P_W),
    .P_N(P_N)
  ) DUT (
    .clk(clk),
    .rst(rst),
    .config_mode(config_mode),
    .config_w_we(config_w_we),
    .config_t_we(config_t_we),
    .config_w_addr(config_w_addr),
    .config_t_addr(config_t_addr),
    .config_w_data(config_w_data),
    .config_t_data(config_t_data),
    .config_np_id(config_np_id),
  
  //// DATA
    .layer_valid_in(layer_valid_in),
    .layer_data_in(layer_data_in),

  // OUTPUTS
    .layer_valid_out(layer_valid_out),
    .layer_ready(layer_ready),
    .layer_data_out(layer_data_out),
    .layer_popcounts(layer_popcounts)
  );

  // VARS
  int test_num;
  int failed;
  int passed;

  logic [P_W-1:0] expected_weights [NUM_NEURONS][BEATS_PER_NEURON];
  logic [MAX_PC_WIDTH-1:0] expected_thresholds [NUM_NEURONS];

  typedef struct {
    logic [P_N-1:0] expected_outputs;
  } expected_result_t;

  expected_result_t expected_queue[$];
 
  // CLOCK GENERATION
  initial begin : gen_clk
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  // MODELS
  function automatic int calc_neuron_output(
    input int neuron_id,
    input logic [NUM_INPUTS-1:0] test_input
  );
    int popcount = 0;
    logic [P_W-1:0] neuron_weights;

    // GATHER ALL WEIGHTS FROM BEATS
    for (int beat = 0; beat < BEATS_PER_NEURON; beat++) begin
      neuron_weights = expected_weights[neuron_id][beat];
    end

    // COMPUTE XNOR RESULT FOR INPUT VS WEIGHTS
    for (int i = 0; i < NUM_INPUTS; i++) begin
      if (test_input[i] == neuron_weights[i]) popcount++;
    end

    return popcount;
  endfunction

  // HELPER TASKS
  task write_weight_beat(
    input int target_np_id,
    input logic [WEIGHT_ADDR_WIDTH-1:0] addr,
    input logic [P_W-1:0] data
  );
    @(posedge clk);
    config_mode <= 1'b1;
    config_w_we <= 1'b1;
    config_np_id <= target_np_id;
    config_w_addr <= addr;
    config_w_data <= data;

    @(posedge clk);
    config_w_we <= 1'b0;
    
  endtask

  task write_threshold(
    input int target_np_id,
    input logic [THRESHOLD_ADDR_WIDTH-1:0] addr,
    input logic [MAX_PC_WIDTH-1:0] data
  );
    @(posedge clk);
    config_mode <= 1'b1;
    config_t_we <= 1'b1;
    config_np_id <= target_np_id;
    config_t_addr <= addr;
    config_t_data <= data;

    @(posedge clk);
    config_t_we <= 1'b0;
  endtask

  task load_random_config();
    $display("[%0t] LOADING RANDOM CONFIGURATION... ", $time);
    @(posedge clk);
    config_mode <= 1'b1;

    for (int neuron = 0;  neuron < NUM_NEURONS; neuron++) begin
      automatic int target_np = (neuron % P_N);
      automatic int neuron_in_np = (neuron / P_N);
      automatic logic [P_W-1:0] weight_data;
      automatic int weight_addr;
      automatic logic [MAX_PC_WIDTH-1:0] threshold_data;
      automatic int threshold_addr;

      for (int beat = 0; beat < BEATS_PER_NEURON; beat++) begin
        weight_data = $urandom;
        weight_addr = neuron_in_np * BEATS_PER_NEURON + beat;
        expected_weights[neuron][beat] = weight_data;

	@(posedge clk);
	config_np_id <= target_np;
	config_w_we <= 1'b1;
	config_w_data <= weight_data;
	config_w_addr <= weight_addr;
	  
      end

      threshold_data = $urandom_range(0, NUM_INPUTS);
      threshold_addr = neuron_in_np;

      expected_thresholds[neuron] = threshold_data;

      @(posedge clk);
      config_w_we <= 1'b1;
      config_t_we <= 1'b1;
      config_np_id <= target_np;
      config_t_addr <= threshold_addr;
      config_t_data <= threshold_data;

    end

    @(posedge clk);
    config_mode <= 1'b0;
    config_t_we <= 1'b0;
    config_w_we <= 1'b0;

    $display("[%0t] CONFIGURATION LOADED: %0d NEURONS", $time, NUM_NEURONS);
  endtask

  task send_input_beat(
	  input logic [P_W-1:0] data, 
	  input logic is_last,
	  input logic ready
  );

    @(posedge clk iff ready);
    layer_valid_in <= 1'b1;
    layer_data_in <= data;
    @(posedge clk);
    layer_valid_in <= 1'b0;
  endtask

  task send_test_input(
    input logic [NUM_INPUTS-1:0] test_input,
    input logic ready
  );
    automatic logic [P_N-1:0] expected_outputs;
    automatic expected_result_t exp;
    automatic int neuron_id;
    automatic int popcount;


    for (int np=0; np < P_N; np++) begin
      neuron_id = 0 * P_N + np;
      popcount = calc_neuron_output(neuron_id, test_input);
      expected_outputs[np] = (popcount >= expected_thresholds[neuron_id]) ? 1'b1 : 1'b0;
    end

    exp.expected_outputs = expected_outputs;
    expected_queue.push_back(exp);

    for (int beat = 0; beat < BEATS_PER_NEURON; beat++) begin
      automatic logic [P_W-1:0] beat_data = test_input[beat*P_W +: P_W];
      automatic logic is_last = (beat == BEATS_PER_NEURON-1);
      send_input_beat(beat_data, is_last, ready); 
    end

    @(posedge clk);
    layer_valid_in <= 1'b0;
  endtask

  task check_output();
    while (!layer_valid_out) @(posedge clk iff !rst);

    if (expected_queue.size() > 0) begin
      automatic expected_result_t exp = expected_queue.pop_front();

      if (layer_data_out == exp.expected_outputs) begin
        $display("[%0t][PASS] %d", $time, test_num);
	$display("EXPECTED: %b | GOT: %b", exp.expected_outputs, layer_data_out);
        passed++;
      end else begin
	$display("[%0t][FAIL] %d", $time, test_num);
	$display("EXPECTED: %b | GOT: %b", exp.expected_outputs, layer_data_out);
	for (int np = 0; np < P_N; np++) begin
          $display("NP[%0d]: POPCOUNT=%0d, THRESHOLD=%0d, OUTPUT=%b", np, layer_popcounts[np], expected_thresholds[np], layer_data_out[np]);
	end
	failed++;
      end
    end else begin
      $display("[%0t][ERROR] UNEXPECTED OUTPUT: %b", $time, layer_data_out);
      failed++;
    end 
  endtask

  task clear_inputs();
    rst <= 1'b1;
    config_mode <= 1'b0;
    config_w_we <= 1'b0;
    config_t_we <= 1'b0;
    config_w_addr <= '0;
    config_t_addr <= '0;
    config_t_data <= '0;
    config_w_data <= '0;
    config_np_id <= '0;
    layer_data_in <= '0;
    layer_valid_in <= 1'b0;
  endtask

  // INIT DUT
  task init_dut();
    $timeformat(-9, 0, " ns");
    rst <= 1'b1;
    repeat (5) @(posedge clk);
    @(negedge clk);
    rst <= 1'b0;
    repeat (2) @(posedge clk);
  endtask

  // DONE MON
  initial begin : done_mon 
    forever begin
      @(posedge clk iff !rst);
      if (layer_valid_out && expected_queue.size() > 0) check_output(); 
    end
  end 

  // TIMEOUT TIMER
  initial begin : timeout
    #1000000
    $display("[ERROR] TIMEOUT");
    disable gen_clk;
  end

  // WAVEFORM DUMP
  initial begin : dump_vcd
    $dumpfile("layer_tb.vcd");
    $dumpvars(0, layer_tb);
  end

  // TESTS
  initial begin : stimulus
    test_num = 0;
    passed = 0;
    failed = 0;
    
    clear_inputs();
    init_dut();
    $display("==================================");
    $display("LAYER PROCESSOR TESTBENCH");
    $display("NUM NEURONS = %0d,", NUM_NEURONS);
    $display("NUM INPUTS = %0d,", NUM_INPUTS);
    $display("P_N = %0d", P_N);
    $display("P_W = %0d", P_W);
    $display("==================================");

    // LOAD RANDOM CONFIG
    $display("LOADING RANDOM CONFIGURATION", test_num);
    load_random_config();
    repeat (5) @(posedge clk);
    $display("CONFIGURATION COMPLETE");

    // TEST2 : SIMPLE INFERENCE ALL ONES
    test_num++;
    $display("TEST %0d: ALL ONES INPUT", test_num);
    send_test_input('1, layer_ready);
    repeat (10) @(posedge clk);
    
    // TEST3 : SIMPLE INFERENCE ALL ZEROS
    test_num++;
    $display("TEST %0d: ALL ZEROS INPUT", test_num);
    send_test_input(0, layer_ready);
    repeat (10) @(posedge clk);

    // TEST4 : MULTIPLE SEQUENTIAL INPUTS
    test_num++;
    $display("TEST %0d: MULTIPLE SEQUENTIAL INPUTS", test_num);
    send_test_input($random, layer_ready);
    send_test_input($random, layer_ready);
    send_test_input($random, layer_ready);
    repeat (20) @(posedge clk);


    // WAIT FOR OUTPUTS
    $display("\nWAITING FOR ALL OUTPUTS...");
    while(expected_queue.size() > 0) @(posedge clk iff !rst);
    repeat (10) @(posedge clk iff !rst);

    $display("==================================");
    $display("TEST SUMMARY");
    $display("==================================");
    $display("TOTAL TESTS = %0d,", passed + failed);
    $display("PASSED = %0d,", passed);
    $display("FAILED = %0d,", failed);
    $display("==================================");

    disable gen_clk;

  end  

endmodule
