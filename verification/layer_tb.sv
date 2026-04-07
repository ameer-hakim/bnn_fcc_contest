`timescale 1ns / 10ps

module layer_tb;

  localparam int NUM_TESTS = 10;
  localparam int LAYER_ID = 0;
  localparam int NUM_INPUTS = 8;   
  localparam int NUM_NEURONS = 12;  
  localparam int P_N = 4;
 
  // Calculated values to go with DUT localparams         
  localparam int MAX_PC_WIDTH = $clog2(NUM_INPUTS + 1);
  localparam int P_W = NUM_INPUTS;
  localparam int NEURONS_PER_NP = (NUM_NEURONS / P_N);
  localparam int WEIGHT_ADDR_WIDTH = $clog2(NEURONS_PER_NP);
  localparam int THRESHOLD_ADDR_WIDTH = $clog2(NEURONS_PER_NP);


  // DUT Hookups
  logic clk = 1'b0;
  logic rst;
  
  logic                            config_mode;
  logic                            config_w_we;
  logic                            config_t_we;
  logic [WEIGHT_ADDR_WIDTH-1:0]    config_w_addr;
  logic [THRESHOLD_ADDR_WIDTH-1:0] config_t_addr;
  logic [P_W-1:0]                  config_w_data;
  logic [MAX_PC_WIDTH-1:0]         config_t_data;
  logic [$clog2(P_N)-1:0]           config_np_id;

  logic layer_valid_in;
  logic layer_go_in;
  logic [P_W-1:0] layer_data_in;

  logic layer_go_out;
  logic layer_ready;
  logic layer_last;
  logic layer_valid_out;
  logic [P_N-1:0] layer_data_out;
  logic [MAX_PC_WIDTH-1:0] layer_popcounts[P_N];
  

  // Instantiate DUT
  layer #(
    .NUM_INPUTS(NUM_INPUTS),
    .NUM_NEURONS(NUM_NEURONS),
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
    .layer_go_in(layer_go_in),
    .layer_data_in(layer_data_in),

  // OUTPUTS
    .layer_go_out(layer_go_out),
    .layer_ready(layer_ready),
    .layer_valid_out(layer_valid_out),
    .layer_last(layer_last),
    .layer_data_out(layer_data_out),
    .layer_popcounts(layer_popcounts)
  );

  // TB VARS
  int neuron_count;

  typedef struct { 
    logic [MAX_PC_WIDTH-1:0] layer_popcounts[NUM_NEURONS];
    logic [NUM_NEURONS-1:0] layer_data_out;
  } dut_t;
  
  // MAILBOXES	
  mailbox driver_mailbox = new;
  mailbox scoreboard_input_mailbox = new;;
  mailbox scoreboard_output_mailbox = new;

  // TEST ITEM
  class layer_item;
 
    rand logic [P_W-1:0] x;
    rand logic [P_W-1:0] w[];

    rand logic [MAX_PC_WIDTH-1:0] thresholds[];


    constraint c_len {
      w.size() == NUM_NEURONS;
      thresholds.size() == NUM_NEURONS;
    }

  endclass


  // FUNCTIONS
  function int compute_popcount (
    input logic [P_W-1:0] x, 
    input logic [P_W-1:0] w
  );
    automatic logic [P_W-1:0] xnor_result = ~(x^w);
    automatic int sum = 0;

    for (int i=0; i<P_W; i++) begin
      sum = sum + xnor_result[i];
    end

    return sum;

  endfunction

  function void compute_output (
    input logic [P_W-1:0] x, 
    input logic [P_W-1:0] w[NUM_NEURONS], 
    input logic [MAX_PC_WIDTH-1:0] t[NUM_NEURONS], 
    output logic [NUM_NEURONS-1:0] y, 
    output logic [MAX_PC_WIDTH-1:0] pc[NUM_NEURONS]
  );

  // COMPUTE POPCOUNTS
  for (int i=0; i<NUM_NEURONS; i++) begin
    pc[i] = compute_popcount(x, w[i]);
    y[i] = (pc[i] >= t[i]) ? 1'b1 : 1'b0;
  end

  endfunction

  // TASKS 
  task send_input_beat(
	  input logic [P_W-1:0] data 
  );

    @(posedge clk);
    layer_go_in <= 1'b1;
    @(posedge clk);
    layer_go_in <= 1'b0;
    layer_data_in <= data;
    layer_valid_in <= 1'b1;
    @(posedge clk);
    layer_valid_in <= 1'b0;
    layer_data_in <= '0;

  endtask

  task load_config(input layer_item item);
    $display("[%0t] LOADING RANDOM CONFIGURATION... ", $time);
    @(posedge clk iff !rst);
    config_mode <= 1'b1;

    for (int neuron = 0;  neuron < NUM_NEURONS; neuron++) begin
      automatic int target_np = (neuron % P_N);
      automatic int neuron_in_np = (neuron / P_N);
      automatic logic [P_W-1:0] weight_data;
      automatic int weight_addr;
      automatic logic [MAX_PC_WIDTH-1:0] threshold_data;
      automatic int threshold_addr;


      config_np_id <= target_np;
      config_w_we <= 1'b1;
      config_w_data <= item.w[neuron];
      config_w_addr <= neuron_in_np;
	  
      config_t_addr <= neuron_in_np;
      config_t_data <= item.thresholds[neuron];

      config_w_we <= 1'b1;
      config_t_we <= 1'b1;
      @(posedge clk iff !rst);

    end

    @(posedge clk iff !rst);
    config_mode <= 1'b0;
    config_t_we <= 1'b0;
    config_w_we <= 1'b0;
    repeat (5) @(posedge clk);

    $display("[%0t] CONFIGURATION LOADED: %0d NEURONS", $time, NUM_NEURONS);
  endtask

  // CLOCK
  initial begin : gen_clk
    forever #5 clk = ~clk;
  end

  // INIT DUT
  initial begin : init_dut
    $timeformat(-9, 0, " ns");

    $display("[%0t] INITIALIZING DUT...", $time);
    rst <= 1'b1;
    layer_valid_in <= 1'b0;
    layer_data_in <= '0;
    layer_go_in <= '0;
    repeat (5) @(posedge clk);
    @(negedge clk);
    rst <= 1'b0;
    $display("[%0t] INITIALIZION COMPLETE...", $time);

  end


  // GENERATOR
  initial begin : generator
    layer_item test;
    for (int i=0; i<NUM_TESTS; i++) begin
      test = new();
      assert (test.randomize()) 
      else $fatal("FAILED TO RANDOMIZE TEST");
      driver_mailbox.put(test);
     end
  end

  // DRIVER
  initial begin : driver
    layer_item item;

     @(posedge clk iff !rst); 
     forever begin
       driver_mailbox.get(item);
       scoreboard_input_mailbox.put(item);

       @(posedge clk iff layer_ready);
       load_config(item);
       layer_go_in <= 1'b1;
       @(posedge clk);
       layer_data_in <= item.x;
       layer_go_in <= 1'b0;
       layer_valid_in <= 1'b1;
       @(posedge clk);
       layer_valid_in <= 1'b0;
     end
     
  end 


  // DONE MONITOR
  initial begin : done_monitor
    dut_t result;
    neuron_count = 0;

    forever begin	
      @(posedge clk iff layer_valid_out);
     
      for (int i=0; i<P_N; i++) begin
        result.layer_popcounts[neuron_count + i] = layer_popcounts[i];
        result.layer_data_out[neuron_count + i] = layer_data_out[i];
      end  

      neuron_count += P_N;

      //if (LOG_OUTPUTS) $display("[%0t] Stored neurons [%0d:%0d], ", $time, neuron_count-P_N, neuron_count-1);

      if (layer_last) begin
        scoreboard_output_mailbox.put(result);
	neuron_count = 0;
	result = '{default : 0};
      end

    end
  end

  // SCOREBOARD
  initial begin : scoreboard
    automatic int passed = 0;
    automatic int failed = 0;    

    dut_t expected_result;
    dut_t actual_result;
    layer_item test_input;

    for (int i=0; i<NUM_TESTS; i++) begin
      test_input = new();
      scoreboard_input_mailbox.get(test_input); 
      scoreboard_output_mailbox.get(actual_result);
      
      compute_output(test_input.x, test_input.w, test_input.thresholds, expected_result.layer_data_out, expected_result.layer_popcounts);


      if (expected_result.layer_popcounts == actual_result.layer_popcounts) begin
        if (expected_result.layer_data_out == actual_result.layer_data_out) begin
          $display("[%0t][PASS] ", $time);
          passed++;
        end else begin 
	  $display("[%0t][FAIL][Y] ACTUAL= %b, EXPECTED= %b", $time, actual_result.layer_data_out, expected_result.layer_data_out);
          failed++;
	end

      end else begin 
	  $display("[%0t][FAIL][POPCOUNT] ACTUAL= %p, EXPECTED= %p", $time, actual_result.layer_popcounts, expected_result.layer_popcounts);
	  failed++;
      end
    end
    $display("=========================RESULTS============================");
    $display("TESTS COMPLETED: %0d PASSED, %0d FAILED", passed, failed);
    $display(" "); 
    $display("============================================================");

    disable gen_clk;
      
  end

endmodule
