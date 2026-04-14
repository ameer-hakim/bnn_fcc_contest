// AMEER HAKIM
// bnn.sv
// Concatenated layers for implementation into bnn_fcc.sv

// PACKAGES
`include "bnn_fcc_pkg.svh"

module bnn #(
  // PARAMETERS
  parameter int TOTAL_LAYERS = 4,                                                       // Includes input, hidden, and output
  parameter int TOPOLOGY[TOTAL_LAYERS] = '{0: 784, 1: 256, 2: 256, 3: 10, default: 0},  // 0: input, TOTAL_LAYERS-1: output
  parameter int NP_CYCLES = 1,                                                          // NEURONS / P_N = NP_CYCLES -> P_N = NEURONS / NP_CYCLES

  // LOCALPARAMS
  localparam int LAYER_PN[TOTAL_LAYERS] = '{
    0: 0,
    1: get_pn(TOPOLOGY[1], NP_CYCLES),
    2: get_pn(TOPOLOGY[2], NP_CYCLES),
    3: get_pn(TOPOLOGY[3], NP_CYCLES),
    default : 0
  },
  localparam int MAX_PW = TOPOLOGY[0],
  localparam int MAX_PN = LAYER_PN[1],
  localparam int MAX_PC_WIDTH = $clog2(LAYER_PN[1]) + 1

)(
  // CLK AND RST
  input logic clk,
  input logic rst,

  // CONFIGURATION
  input logic [$clog2(TOTAL_LAYERS)-1:0] layer_sel,
  input logic config_mode,
  input logic config_w_we,
  input logic config_t_we, 
  input logic [NP_CYCLES-1:0] config_w_addr,
  input logic [NP_CYCLES-1:0] config_t_addr,
  input logic [LAYER_PN[1]-1:0] config_w_data,
  input logic [LAYER_PN[1]-1:0] config_t_data,
  input logic [LAYER_PN[1]-1:0] config_np_id, // Size signal for largest num of NP's

  // INPUTS
  input logic [(TOPOLOGY[0])-1:0] bnn_data_in,
  input logic bnn_valid_in,

  // OUTPUTS
  output logic [$clog2(LAYER_PN[2]+1)-1:0] bnn_popcounts [LAYER_PN[3]],
  output logic [LAYER_PN[3]-1:0] bnn_data_out,
  output logic bnn_last,
  output logic bnn_valid_out
);

  // LAYER SIGNAL ARRAYS
  logic [TOTAL_LAYERS-1:0] layer_en = '1;
  logic [TOTAL_LAYERS-1:0] layer_ready;
  logic [TOTAL_LAYERS-1:0] layer_go_out;
  logic [TOTAL_LAYERS-1:0] layer_valid_out;
  logic [TOTAL_LAYERS-1:0] layer_last;

  // WASTED TOO MUCH TIME TRYING TO GET GENERATE TO CLEANLY MAP SIGNALS
  // DOING IT THIS INELOQUENT WAY FOR MY SANITY
  logic [$clog2(TOPOLOGY[0]+1)-1:0] layer1_pc [LAYER_PN[1]];
  logic [$clog2(LAYER_PN[1]+1)-1:0] layer2_pc [LAYER_PN[2]];
  logic [$clog2(LAYER_PN[2]+1)-1:0] layer3_pc [LAYER_PN[3]];

  logic [LAYER_PN[1]-1:0] layer1_data;
  logic [LAYER_PN[2]-1:0] layer2_data;
  logic [LAYER_PN[3]-1:0] layer3_data;

  // INPUT LAYER
  logic input_go_out_r;
  logic input_valid_in_r, input_valid_out_r;
  logic [TOPOLOGY[0]-1:0] input_data_in_r, input_data_out_r; 

  // COMBO LOGIC
  //always_comb begin 
  //  // LAYER ENABLE LOGIC
  //  for (int i=0; i<TOTAL_LAYERS-1; i++) begin
  //    layer_en[i] = !(layer_go_out[i] & layer_ready[i+1]); 
  //  end
  //end


  // SEQUENTIAL LOGIC
  always_ff @(posedge clk, posedge rst) begin
    if (layer_en[0]) begin
      if (bnn_valid_in) input_data_in_r <= bnn_data_in;

      input_valid_in_r <= bnn_valid_in;
      input_valid_out_r <= input_valid_in_r;

      if (bnn_valid_in) input_data_in_r  <= bnn_data_in;
      if (input_valid_in_r) input_data_out_r <= input_data_in_r;

      input_go_out_r <= bnn_valid_in;
    end
    
    if (rst) begin
      input_data_in_r  <= '0;
      input_data_out_r <= '0;

      input_valid_in_r <= 1'b0;
      input_valid_out_r <= 1'b0;

      input_go_out_r <= 1'b0;
    end

  end

  // INSTANTIATE LAYERS
  //// HIDDEN LAYERS
  for (genvar i=1; i<TOTAL_LAYERS; i++) begin : g_config

    // CONFIG DEMUX
    logic cl_mode_i;
    logic cl_t_we_i;
    logic cl_w_we_i;
    
    assign cl_mode_i = config_mode && (layer_sel == i);
    assign cl_w_we_i = config_w_we && (layer_sel == i);
    assign cl_t_we_i = config_t_we && (layer_sel == i);

  end

  layer #(
    // PARAMETERS
    .LAYER_ID   (1),
    .NUM_INPUTS (TOPOLOGY[0]),
    .NUM_NEURONS(TOPOLOGY[1]),
    .P_N        (LAYER_PN[1])
  ) layer1 (
    // CLK AND RST
    .clk(clk),
    .rst(rst),
  
    // INPUTS
    //// CONFIGURATION INTERFACE
    .config_mode  (g_config[1].cl_mode_i),
    .config_w_we  (g_config[1].cl_w_we_i),
    .config_t_we  (g_config[1].cl_t_we_i),
    .config_w_addr(config_w_addr),
    .config_t_addr(config_t_addr),
    .config_w_data(config_w_data),
    .config_t_data(config_t_data),
    .config_np_id (config_np_id),
    
    //// DATA
    .layer_en(layer_en[1]),
    .layer_valid_in(input_valid_out_r),
    .layer_go_in   (input_go_out_r),
    .layer_data_in (input_data_out_r),
  
    // OUTPUTS
    .layer_go_out   (layer_go_out[1]),
    .layer_ready    (layer_ready[1]),
    .layer_last     (layer_last[1]),
    .layer_valid_out(layer_valid_out[1]),
    .layer_data_out (layer1_data),
    .layer_popcounts(layer1_pc)
  );

  layer #(
    // PARAMETERS
    .LAYER_ID   (2),
    .NUM_INPUTS (LAYER_PN[1]),
    .NUM_NEURONS(TOPOLOGY[2]),
    .P_N        (LAYER_PN[2])
  ) layer2 (
    // CLK AND RST
    .clk(clk),
    .rst(rst),
  
    // INPUTS
    //// CONFIGURATION INTERFACE
    .config_mode  (g_config[2].cl_mode_i),
    .config_w_we  (g_config[2].cl_w_we_i),
    .config_t_we  (g_config[2].cl_t_we_i),
    .config_w_addr(config_w_addr),
    .config_t_addr(config_t_addr),
    .config_w_data(config_w_data),
    .config_t_data(config_t_data),
    .config_np_id (config_np_id),
    
    //// DATA
    .layer_en(layer_en[2]),
    .layer_valid_in(layer_valid_out[1]),
    .layer_go_in   (layer_go_out[1]),
    .layer_data_in (layer1_data),
  
    // OUTPUTS
    .layer_go_out   (layer_go_out[2]),
    .layer_ready    (layer_ready[2]),
    .layer_last     (layer_last[2]),
    .layer_valid_out(layer_valid_out[2]),
    .layer_data_out (layer2_data),
    .layer_popcounts(layer2_pc)
  );

  layer #(
    // PARAMETERS
    .LAYER_ID   (3),
    .NUM_INPUTS (LAYER_PN[2]),
    .NUM_NEURONS(TOPOLOGY[3]),
    .P_N        (LAYER_PN[3])
  ) layer3 (
    // CLK AND RST
    .clk(clk),
    .rst(rst),
  
    // INPUTS
    //// CONFIGURATION INTERFACE
    .config_mode  (g_config[3].cl_mode_i),
    .config_w_we  (g_config[3].cl_w_we_i),
    .config_t_we  (g_config[3].cl_t_we_i),
    .config_w_addr(config_w_addr),
    .config_t_addr(config_t_addr),
    .config_w_data(config_w_data),
    .config_t_data(config_t_data),
    .config_np_id (config_np_id),
    
    //// DATA
    .layer_en(layer_en[3]),
    .layer_valid_in(layer_valid_out[2]),
    .layer_go_in   (layer_go_out[2]),
    .layer_data_in (layer2_data),
  
    // OUTPUTS
    .layer_go_out   (layer_go_out[3]),
    .layer_ready    (layer_ready[3]),
    .layer_last     (layer_last[3]),
    .layer_valid_out(layer_valid_out[3]),
    .layer_data_out (layer3_data),
    .layer_popcounts(layer3_pc)
  );

  // ASSIGN OUTPUTS
  assign bnn_data_out  = layer3_data;
  assign bnn_popcounts = layer3_pc;
  assign bnn_last      = layer_last[3];
  assign bnn_valid_out = layer_valid_out[3];

endmodule
