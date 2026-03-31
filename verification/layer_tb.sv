`timescale 1ns / 10ps

module layer_tb;

  localparam int CLK_PERIOD = 10;  // 10ns = 100MHz
 
  // Start with small topology for easier debugging
  localparam int LAYER_ID = 0;
  localparam int NUM_INPUTS = 8;    // Small for testing
  localparam int NUM_NEURONS = 8;   // Small for testing
  localparam int P_W = 8;             // 8 parallel weights
  localparam int P_N = 4;             // 4 parallel neurons
 
  // Calculated values to go with DUT localparams
  localparam int MAX_PC_WIDTH = $clog2(NUM_INPUTS + 1);
  localparam int NEURONS_PER_NP = (NUM_NEURONS / P_N);
  localparam int BEATS_PER_NEURON = (NUM_INPUTS / P_W);
  localparam int WEIGHT_ADDR_WIDTH = $clog2(NEURONS_PER_NP * BEATS_PER_NEURON);
  localparam int THRESHOLD_ADDR_WIDTH = $clog2(NEURONS_PER_NP);

  // DUT hookups
  logic clk = 1'b0;
  logic rst;

  logic config_mode;
  logic config_we_w;
  logic config_we_t;
  logic [WEIGHT_ADDR_WIDTH-1:0] config_addr_w;
  logic [THRESHOLD_ADDR_WIDTH-1:0] config_addr_t;
  logic [P_W-1:0] config_data_w;
  logic [MAX_PC_WIDTH-1:0] config_data_t;
  logic [$clog2(P_N)-1:0] config_np_id;
  
  logic layer_valid_in;
  logic layer_last_in;
  logic [P_W-1:0] layer_data_in;

  logic layer_valid_out;
  logic [P_N-1:0] layer_data_out;
  logic [P_W-1:0] layer_popcounts[P_N];

  // Instantiate DUT
  layer #(
    .NUM_INPUTS(784),
    .NUM_NEURONS(256),
    .P_W(8),
    .P_N(8)
  ) DUT (
    .clk(clk),
    .rst(rst),
    .config_mode(config_mode),
    .config_we_w(config_we_w),
    .config_we_t(config_we_t),
    .config_addr_w(config_addr_w),
    .config_addr_t(config_addr_t),
    .config_data_w(config_data_w),
    .config_data_t(config_data_t),
    .config_np_id(config_np_id),
    .layer_valid_in(layer_valid_in),
    .layer_last_in(layer_last_in),
    .layer_data_in(layer_data_in),
    .layer_valid_out(layer_valid_out),
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

  expected_result_t expected_queue[NUM_NEURONS];
 
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
    logic [NUM_INPUTS-1:0] neuron_weights;

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
    config_we_w <= 1'b1;
    config_np_id <= target_np_id;
    config_addr_w <= addr;
    config_data_w <= data;

    @(posedge clk);
    config_we_w <= 1'b0;
    
  endtask

  task write_threshold(
    input int target_np_id,
    input logic [THRESHOLD_ADDR_WIDTH-1:0] addr,
    input logic [MAX_PC_WIDTH-1:0] data
  );
    @(posedge clk);
    config_mode <= 1'b1;
    config_we_t <= 1'b1;
    config_np_id <= target_np_id;
    config_addr_t <= addr;
    config_data_t <= data;

    @(posedge clk);
    config_we_t <= 1'b0;
  endtask

  task load_random_config();
    $display("[%0t] LOADING RANDOM CONFIGURATION... ", $time);
    @(posedge clk);
    config_mode <= 1'b1;

    for (int neuron = 0;  neuron < NUM_NEURONS; neuron++) begin
      automatic int target_np = (neuron % P_N);
      automatic int neuron_in_np = (neuron / P_N);

      for (int beat = 0; beat < BEATS_PER_NEURON; beat++) begin
        automatic logic [P_W-1:0] weight_data = $urandom;
        automatic int weight_addr = neuron_in_np * BEATS_PER_NEURON + beat;
        expected_weights[neuron][beat] = weight_data;

	@(posedge clk);
	config_np_id <= target_np;
	config_we_w <= 1'b1;
	config_data_w <= weight_data;
	config_addr_w <= weight_addr;
	  
      end

      automatic logic [MAX_PC_WIDTH-1:0] threshold_data = $urandom_range(0, NUM_INPUTS);
      automatic int threshold_addr = neuron_in_np;

      expected_thresholds[neuron] = threshold_data;

      @(posedge clk);
      config_we_w <= 1'b1;
      config_we_t <= 1'b1;
      config_np_id <= target_np;
      config_addr_t <= threshold_addr;
      config_data_t <= threshold_data;

    end

    @(posedge clk);
    config_mode <= 1'b0;
    config_we_t <= 1'b0;
    config_we_w <= 1'b0;

    $display("[%0t] CONFIGURATION LOADED: %0d NEURONS", $time, NUM_NEURONS);
  endtask

  task send_test_input(
    input logic [NUM_INPUTS-1:0] test_input,
  );
    automatic logic [P_N-1:0] expected_outputs;

    for (int np=0; np < P_N; np++) begin
      int neuron_id = 0 * P_N + np;
      int popcount = calc_neuron_output(neuron_id, test_input);
      expected_outputs[np] = (popcount >= expected_thresholds[neuron_id]) ? 1'b1 : 1'b0;
    end

    expected_result_t exp;
    exp.expected_outputs = expected_outputs;
    exp_queue.push_back(exp);

    for (int beat = 0; beat < BEATS_PER_NEURON; beat++) begin
      logic [P_W-1:0] beat_data = test_input[beat*P_W +: PW];
      logic is_last = (beat == BEATS_PER_NEURON-1);
      send_input_beat(beat_data, is_last); 
    end

    @(posedge clk);
    layer_valid_in <= 1'b1;
  endtask

  task check_output();
    @(posedge clk iff !layer_valid_out);

    if (expected_queue.size() > 0) begin
      automatic expected_result_t exp = expected_queue.pop_front();

      if (layer_data_out == exp.expected_outputs) begin
        $display("[%0t][PASS] %d", $time, test_num);
	$display("EXPECTED: %b | GOT: %b", exp.expected_outputs, layer_data_out);

	for (int np = 0; np < P_N; np++) begin
          $display("NP[%0d]: POPCOUNT=%0d, THRESHOLD=%0d, OUTPUT=%b", np, layer_popcounts[np], expected_thresholds[np], layer_data_out[np]);
	end
	failed++;
      end
    end else begin
      $display("[%0t][ERROR] UNEXPECTED OUTPUT: %b", layer_data_out);
      failed++;
    end 
  endtask

  task clear_inputs();
    rst <= 1'b1;
    config_mode <= 1'b0;
    config_we_t <= 1'b0;
    config_we_w <= 1'b0;
    config_addr_w <= '0;
    config_addr_w <= '0;
    config_data_w <= '0;
    config_data_t <= '0;
    config_np_id <= '0;
    layer_data_in <= '0;
    layer_valid_in <= 1'b0;
    layer_last_in <= 1'b0;
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
      @(posedge clk);
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
    
    init_dut();
    $display("==================================");
    $display("LAYER PROCESSOR TESTBENCH");
    $display("NUM NEURONS = %0d,", NUM_NEURONS);
    $display("NUM INPUTS = %0d,", NUM_INPUTS);
    $display("P_N = %0d", P_N);
    $display("P_W = %0d", P_W);
    $display("==================================");

    // LOAD CONFIG
    test_num++;
    $display("TEST %0d: LOAD RANDOM CONFIGURATION", test_num);
    load_random_configuration();
    repeat (5) @(posedge clk);
    display("CONFIGURATION COMPLETE");
  end
  

endmodule
