// AMEER HAKIM
// bnn.sv
// CONCATENATED layer.sv MODULES FOR IMPLEMENTATION INTO bnn_fcc.sv
//
`include "bnn_fcc_pkg.svh"

module bnn #(
  // PARAMETERS
  parameter int TOTAL_LAYERS = 4,  // Includes input, hidden, and output
  parameter int TOPOLOGY[TOTAL_LAYERS] = '{0: 784, 1: 256, 2: 256, 3: 10, default: 0},  // 0: input, TOTAL_LAYERS-1: output
  parameter int NP_CYCLES = 1  // NEURONS / P_N = NP_CYCLES -> P_N = NEURONS / NP_CYCLES

  // LOCALPARAMS
  localparam int MAX_PW = get_max_pw(TOTAL_LAYERS, TOPOLOGY, NP_CYCLES)
  localparam int LAYER_PN[TOTAL_LAYERS] = '{
    0: get_pn(TOPOLOGY, 0, NP_CYCLES),
    1: get_pn(TOPOLOGY, 1, NP_CYCLES),
    2: get_pn(TOPOLOGY, 2, NP_CYCLES),
    3: get_pn(TOPOLOGY, 3, NP_CYCLES),
    default : 0
  }

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
  input logic [(TOPOLOGY[0]/NP_CYCLES)-1:0] config_w_data,
  input logic [(TOPOLOGY[0]/NP_CYCLES)-1:0] config_t_data,
  input logic [LAYER_PN[1]-1:0] config_np_id; // Size signal for largest num of NP's

  // INPUTS
  input logic [(TOPOLOGY[0])-1:0] bnn_data_in,
  input logic bnn_valid_in,

  // OUTPUTS
  output logic [(TOPOLOGY[TOTAL_LAYERS-2] / NP_CYCLES)-1:0][TOPOLOGY[TOTAL_LAYERS-1] / NP_CYCLES] bnn_popcounts,
  output logic [(TOPOLOGY[TOTAL_LAYERS-1] / NP_CYCLES)-1:0] bnn_data_out,
  output logic bnn_last,
  output logic bnn_valid_out
);

  // LAYER SIGNAL ARRAYS
  logic [TOTAL_LAYERS-1:0] layer_en;
  logic [TOTAL_LAYERS-1:0] layer_ready;
  logic [TOTAL_LAYERS-1:0] layer_go_out;
  logic [TOTAL_LAYERS-1:0] layer_valid_out;
  logic [TOTAL_LAYERS-1:0] layer_last;

  // INSTANTIATE LAYERS
  //// HIDDEN LAYERS
  for (genvar i=0; i<TOTAL_LAYERS; i++) begin : g_layers

    logic [(i==0)? TOPOLOGY[0] : (LAYER_PN[i])-1:0] layer_data_out;

    logic [((i==0) ? '0 : LAYER_PN[i-1])-1:0]
          [((i==0) ? '0 : LAYER_PN[i])] layer_popcounts;

    logic [TOTAL_LAYERS-1:0] layer_last;
    logic [TOTAL_LAYERS-1:0] layer_valid_out;
    logic [TOTAL_LAYERS-1:0] layer_go_out;


    // CONFIG DEMUX
    logic cl_mode;
    logic cl_t_we;
    logic cl_w_we;
    
    if (i == 0) begin
      assign cl_mode_i = '0;
      assign cl_w_we_i = '0;
      assign cl_t_we_i = '0;
  
    end else begin
      assign cl_mode_i = cf_mode_i && (layer_sel == i);
      assign cl_w_we_i = cl_w_we_i && (layer_sel == i);
      assign cl_t_we_i = cl_t_we_i && (layer_sel == i);

    end
  
    logic [((i>0) ? LAYER_PN[i])-1:0 : 0] cl_w_data;

    assign cl_w_data = cl_w_data[];

    layer #(
      // PARAMETERS
      .LAYER_ID(i),
      .NUM_INPUTS((i==0) ? TOPOLOGY[i] : LAYER_PN[i-1] ),
      .NUM_NEURONS(TOPOLOGY[i]),
      .P_N(LAYER_PN[i])
    ) layers (
      // CLK AND RST
      .clk(clk),
      .rst(rst),
    
      // INPUTS
      //// CONFIGURATION INTERFACE
      .config_mode(cl_mode),
      .config_w_we(cl_w_we),
      .config_t_we(cl_t_we),
      .config_w_addr(config_w_addr),
      .config_t_addr(config_t_addr),
      .config_w_data(config_w_data),
      .config_t_data(config_t_data),
      .config_np_id(config_np_id),
      
      //// DATA
      .layer_en(layer_en[i]),
      .layer_valid_in((i==0) ? bnn_valid_in : layer_valid_out[i-1]),
      .layer_go_in((i==0) ? bnn_valid_in : layer_go_out[i-1]),
      .layer_data_in((i==0) ? bnn_data_in : g_layers[i-1].layer_data_out),
    
      // OUTPUTS
      .layer_go_out(layer_go_out[i]),
      .layer_ready(layer_ready[i]),
      .layer_last(layer_last[i]),
      .layer_valid_out(layer_valid_out),
      .layer_data_out(layer_data_out),
      .layer_popcount(layer_popcounts)
    );
  end

endmodule
