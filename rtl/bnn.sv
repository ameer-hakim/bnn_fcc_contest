// AMEER HAKIM
// bnn.sv
// CONCATENATED layer MODULES FOR IMPLEMENTATION INTO bnn_fcc.sv

module bnn #(
  // PARAMETERS
  parameter int TOTAL_LAYERS = 4,  // Includes input, hidden, and output
  parameter int TOPOLOGY[TOTAL_LAYERS] = '{0: 784, 1: 256, 2: 256, 3: 10, default: 0},  // 0: input, TOTAL_LAYERS-1: output
  parameter int NP_CYCLES = 1

  // LOCALPARAMS
)(
  // CLK AND RST
  input logic clk,
  input logic rst,

  // INPUTS
  input logic [(TOPOLOGY[0])-1:0] bnn_data_in,
  input logic bnn_valid_in,

  // OUTPUTS
  output logic [(TOPOLOGY[TOTAL_LAYERS-2] / NP_CYCLES)-1:0][TOPOLOGY[TOTAL_LAYERS-1] / NP_CYCLES] bnn_popcounts,
  output logic [(TOPOLOGY[TOTAL_LAYERS-1] / NP_CYCLES)-1:0] bnn_y,
  output logic bnn_last,
  output logic bnn_valid_out
);

  logic [TOTAL_LAYERS-1:0] layer_ready;
  logic [TOTAL_LAYERS-1:0] layer_en;
 
  for (genvar i=1; i<TOTAL_LAYERS-1; i++) begin : g_LAYER_SIGNALS
    logic [(TOPOLOGY[i-1] / NP_CYCLES)-1:0][TOPOLOGY[i] / NP_CYCLES] layer_popcounts;
    logic [(TOPOLOGY[i-1] / NP_CYCLES)-1:0] layer_data_out;
  end 

  // GENERATE CONFIGURATION SIGNALS FOR LAYERS
  for (genvar i=1; i<TOTAL_LAYERS; i++) begin
    logic config_mode;
    logic config_w_we;
    logic config_t_we;
    logic [NP_CYCLES-1:0] config_w_addr;
    logic [NP_CYCLES-1:0] config_t_addr;
    logic [(TOPOLOGY[i-1]/NP_CYCLES)-1:0] config_w_data;
    logic config_t_data;
    logic config_np_id;
  end
  always_comb begin
    
  end


  // INSTANTIATE LAYERS
  //// INPUT LAYERS
  layer #(
    // PARAMETERS
    .LAYER_ID(0),
    .NUM_INPUTS(TOPOLOGY[0]),
    .NUM_NEURONS(0)
  ) input_layer (
    // CLK AND RST
    .clk(clk),
    .rst(rst),
  
    // INPUTS
    //// CONFIGURATION INTERFACE
    .config_mode(),
    .config_w_we(),
    .config_t_we(),
    .config_w_addr(), 
    .config_t_addr(),
    .config_w_data(),
    .config_t_data(),
    .config_np_id(),
    
    //// DATA
    .layer_valid_in(),
    .layer_go_in(),
    .layer_data_in(),
  
    // OUTPUTS
    .layer_go_out(),
    .layer_ready(layer_ready[0]),
    .layer_last(),
    .layer_valid_out(),
    .layer_data_out(),
    .layer_popcount()
  );
  //// HIDDEN LAYERS
  for (genvar i=1; i<TOTAL_LAYERS-1; i++) begin : g_layers
    layer #(
      // PARAMETERS
      .LAYER_ID(i),
      .NUM_INPUTS(TOPOLOGY[i-1]),
      .NUM_NEURONS(TOPOLOGY[i]),
      .P_N(TOPOLOGY[i] / NP_CYCLES)
    ) layers (
      // CLK AND RST
      .clk(clk),
      .rst(rst),
    
      // INPUTS
      //// CONFIGURATION INTERFACE
      .config_mode(),
      .config_w_we(),
      .config_t_we(),
      .config_w_addr(),
      .config_t_addr(),
      .config_w_data(),
      .config_t_data(),
      .config_np_id(),
      
      //// DATA
      .layer_valid_in(),
      .layer_go_in(),
      .layer_data_in(),
    
      // OUTPUTS
      .layer_go_out(),
      .layer_ready(layer_ready[i]),
      .layer_last(),
      .layer_valid_out(),
      .layer_data_out(layer_data_out[i]),
      .layer_popcount(layer_popcounts[i])
    );
  end

  layer #(
    // PARAMETERS
    .LAYER_ID(TOTAL_LAYERS-1),
    .NUM_INPUTS(TOPOLOGY[TOTAL_LAYERS-2]),
    .NUM_NEURONS(TOPOLOGY[TOTAL_LAYERS-1])
  ) output_layer (
    // CLK AND RST
    .clk(clk),
    .rst(rst),
  
    // INPUTS
    //// CONFIGURATION INTERFACE
    .config_mode(),
    .config_w_we(),
    .config_t_we(),
    .config_w_addr(),
    .config_t_addr(),
    .config_w_data(),
    .config_t_data(),
    .config_np_id(),
    
    //// DATA
    .layer_valid_in(),
    .layer_go_in(),
    .layer_data_in(),
  
    // OUTPUTS
    .layer_go_out(),
    .layer_ready(layer_ready[TOTAL_LAYERS-1]),
    .layer_last(bnn_last),
    .layer_valid_out(bnn_valid_out),
    .layer_data_out(bnn_y),
    .layer_popcount(bnn_popcounts)
  );

  
  // CONFIGURATION
  always_comb begin

  end

endmodule
