// AMEER HAKIM
// layer.sv
// Binary Neural Net layer module containing NP's, Input Buffer, Weight/Threshold RAMS,
// and Configuration Controller

// questions: do I need to give this a ready output? 
// 
// I might need to make this work so that there is one beat per neuron      

module layer #(
  // PARAMETERS
  parameter int LAYER_ID = 0,
  parameter int NUM_INPUTS = 8,
  parameter int NUM_NEURONS = 8,
  parameter int P_W = 8,
  parameter int P_N = 8,

  // LOCALPARAMS
  localparam int MAX_PC_WIDTH = $clog2(NUM_INPUTS + 1),
  localparam int NEURONS_PER_NP = (NUM_NEURONS / P_N),
  localparam int BEATS_PER_NEURON = (NUM_INPUTS / P_W),
  localparam int WEIGHT_ADDR_WIDTH = $clog2(NEURONS_PER_NP * BEATS_PER_NEURON),
  localparam int THRESHOLD_ADDR_WIDTH = $clog2(NEURONS_PER_NP)

)(
  // CLK AND RST
  input logic clk,
  input logic rst,

  // INPUTS
  //// CONFIGURATION INTERFACE
  input logic config_mode,

  input logic config_we_w,
  input logic config_we_t,

  input logic [WEIGHT_ADDR_WIDTH-1:0] config_addr_w,
  input logic [THRESHOLD_ADDR_WIDTH-1:0] config_addr_t,

  input logic [P_W-1:0] config_data_w,
  input logic [MAX_PC_WIDTH-1:0] config_data_t,

  input logic [$clog2(P_N)-1:0] config_np_id,
  
  //// DATA
  input logic layer_valid_in,
  input logic layer_last_in,
  input logic [P_N-1:0] layer_data_in,

  // OUTPUTS
  output logic layer_valid_out,
  output logic [P_W-1:0] layer_data_out,
  output logic [MAX_PC_WIDTH-1:0] layer_popcounts[P_N]
);

  // REGISTERS
  logic layer_valid_in_r;
  logic layer_last_in_r;
  logic [P_W-1:0] layer_data_in_r;
  logic [$clog2(NEURONS_PER_NP)-1:0] neuron_batch_r;
  logic [$clog2(BEATS_PER_NEURON)-1:0] beat_count_r;

  // RAM ADDR GEN
  logic [WEIGHT_ADDR_WIDTH-1:0] w_inf_addr;
  logic [THRESHOLD_ADDR_WIDTH-1:0] t_inf_addr;


  // RAM CTRL
  logic [P_N-1:0] w_wr_en;
  logic [P_N-1:0] w_rd_en;
  logic [P_N-1:0][WEIGHT_ADDR_WIDTH-1:0] w_wr_addr;
  logic [P_N-1:0][WEIGHT_ADDR_WIDTH-1:0] w_rd_addr;
  logic [P_N-1:0][P_W-1:0] w_wr_data;
  logic [P_N-1:0][P_W-1:0] w_rd_data;
 
  logic [P_N-1:0] t_wr_en;
  logic [P_N-1:0] t_rd_en;
  logic [P_N-1:0][THRESHOLD_ADDR_WIDTH-1:0] t_wr_addr;
  logic [P_N-1:0][THRESHOLD_ADDR_WIDTH-1:0] t_rd_addr;
  logic [P_N-1:0][MAX_PC_WIDTH-1:0] t_wr_data;
  logic [P_N-1:0][MAX_PC_WIDTH-1:0] t_rd_data;

  // NP 
  logic [P_N-1:0] np_valid_out;


  // COMBO LOGIC
  assign w_inf_addr = neuron_batch_r * BEATS_PER_NEURON + beat_count_r; 
  assign t_inf_addr = neuron_batch_r;

  always_comb begin
    for (int i=0; i<P_N; i++) begin
      if (config_mode) begin
        w_wr_en[i] = (config_np_id == i) && config_we_w;
        w_wr_addr[i] = config_addr_w;
        w_wr_data[i] = config_data_w;

        t_wr_en[i] = (config_np_id == i) && config_we_t;
        t_wr_addr[i] = config_addr_t;
        t_wr_data[i] = config_data_t;

        w_rd_en[i] = 1'b0;
        w_rd_addr[i] = '0;
       
        t_rd_en[i] = 1'b0;
        t_rd_addr[i] = '0;

      end else begin
        w_wr_en[i] = 1'b0;
        w_wr_addr[i] = '0;
        w_wr_data[i] = '0;

        t_wr_en[i] = 1'b0;
        t_wr_addr[i] = '0;
        t_wr_data[i] = '0;

        w_rd_en[i] = layer_valid_in;
        w_rd_addr[i] = w_inf_addr;
       
        t_rd_en[i] = layer_valid_in;
        t_rd_addr[i] = t_inf_addr;

      end
    end
  end


  // SEQUENTIAL LOGIC
  always_ff @(posedge clk, posedge rst) begin
    if (rst) begin
      neuron_batch_r <= '0;
      beat_count_r <= '0;
      layer_data_in_r <= '0; 
      layer_valid_in_r <= 1'b0;
      layer_last_in_r <= 1'b0;
    end else begin
      layer_valid_in_r <= layer_valid_in;
      layer_last_in_r <= layer_last_in;
      if (!config_mode && layer_valid_in) begin
	layer_data_in_r <= layer_data_in;
        if (layer_last_in) begin
          beat_count_r <= '0;
          
          if (neuron_batch_r >= NEURONS_PER_NP - 1) begin
            neuron_batch_r <= '0;
          end else begin
            neuron_batch_r <= neuron_batch_r + 1'b1; 
          end
        end else begin
          beat_count_r <= beat_count_r + 1'b1;
        end
      end
    end 
  end

  // GEN RAMS
  for (genvar i=0; i<P_N; i++) begin : g_RAMS
    // WEIGHT RAMS
    ram_sdp #( 
      .DATA_WIDTH(P_W),
      .ADDR_WIDTH(WEIGHT_ADDR_WIDTH),
      .REG_RD_DATA(1'b0),
      .WRITE_FIRST(1'b0),
      .STYLE("block")
    ) W_RAM (
      .clk(clk),
      .rd_en(w_rd_en[i]),
      .rd_addr(w_rd_addr[i]),
      .rd_data(w_rd_data[i]),
      .wr_en(w_wr_en[i]),
      .wr_addr(w_wr_addr[i]),
      .wr_data(w_wr_data[i])
    );

    // THRESHOLD RAMS
    ram_sdp #( 
      .DATA_WIDTH(MAX_PC_WIDTH),
      .ADDR_WIDTH(THRESHOLD_ADDR_WIDTH),
      .REG_RD_DATA(1'b0),
      .WRITE_FIRST(1'b0),
      .STYLE("block")
    ) T_RAM (
      .clk(clk),
      .rd_en(t_rd_en[i]),
      .rd_addr(t_rd_addr[i]),
      .rd_data(t_rd_data[i]),
      .wr_en(t_wr_en[i]),
      .wr_addr(t_wr_addr[i]),
      .wr_data(t_wr_data[i])
    );
  end

  // GEN NP's
  for (genvar i=0; i<P_N; i++) begin : g_NP
    binary_neuron_p #(
      .P_W(P_W),
      .MAX_PC_WIDTH(MAX_PC_WIDTH)
    ) NP (
      .clk(clk),
      .rst(rst),
      .x(layer_data_in_r),
      .w(w_rd_data[i]),
      .threshold(t_rd_data[i]),
      .valid_in(layer_valid_in_r),
      .last(layer_last_in_r),
      .valid_out(np_valid_out[i]),
      .y(layer_data_out[i]),
      .popcount(layer_popcounts[i])
    );

  end

  // ASSIGN OUTPUTS
  assign layer_valid_out = np_valid_out[0];

endmodule
