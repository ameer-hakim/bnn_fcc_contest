// AMEER HAKIM
// layer.sv
// Binary Neural Net layer module containing NP's, Input Buffer, Weight/Threshold RAMS,
// and Configuration Controller
//
// THIS ASSUMES THAT THE P_N OF THE PREVIOUS LAYER == P_W OF THE CURRENT LAYER 
// ASSUMES ALL LAYERS HAVE THE SAME NEURONS_PER_BEAT

module layer #(
  // PARAMETERS
  parameter int LAYER_ID    = 0,
  parameter int NUM_INPUTS  = 8,
  parameter int NUM_NEURONS = 8,
  parameter int P_N         = 8,

  // LOCALPARAMS
  localparam int P_W                  = NUM_INPUTS,
  localparam int MAX_PC_WIDTH         = $clog2(NUM_INPUTS + 1),
  localparam int NEURONS_PER_NP       = (NUM_NEURONS / P_N),
  localparam int WEIGHT_ADDR_WIDTH    = $clog2(NEURONS_PER_NP),
  localparam int THRESHOLD_ADDR_WIDTH = $clog2(NEURONS_PER_NP),
  localparam int NP_LATENCY           = $clog2(P_W) + 2,
  localparam int LAST_DELAY           = NP_LATENCY + 2

)(
  // CLK AND RST
  input logic clk,
  input logic rst,

  // INPUTS
  //// CONFIGURATION INTERFACE
  input logic                            config_mode,
  input logic                            config_w_we,
  input logic                            config_t_we,
  input logic [WEIGHT_ADDR_WIDTH-1:0]    config_w_addr,
  input logic [THRESHOLD_ADDR_WIDTH-1:0] config_t_addr,
  input logic [P_W-1:0]                  config_w_data,
  input logic [MAX_PC_WIDTH-1:0]         config_t_data,
  input logic [$clog2(P_N)-1:0]          config_np_id,
  
  //// DATA
  input logic layer_en,
  input logic layer_valid_in,
  input logic layer_go_in,
  input logic [P_W-1:0] layer_data_in,

  // OUTPUTS
  output logic layer_go_out,
  output logic layer_ready,
  output logic layer_last,
  output logic layer_valid_out,
  output logic [P_N-1:0] layer_data_out,
  output logic [MAX_PC_WIDTH-1:0] layer_popcounts[P_N]
);

  generate
    if (NUM_NEURONS != 0) begin
      // SIGNALS
      //// DATAPATH
      logic [MAX_PC_WIDTH-1:0] layer_popcounts_r[P_N];
      logic [P_W-1:0] layer_data_in_r;
      logic [P_N-1:0] layer_data_out_r;
      logic layer_valid_out_r;
      logic np_valid_r;
      logic np_last_r;
      logic [P_N-1:0] np_y;
      logic [MAX_PC_WIDTH-1:0] np_popcounts[P_N];

      //// ADDRESS GENERATOR
      logic go_r;
      logic done_r;
      logic [$clog2(NEURONS_PER_NP)-1:0] neuron_count_r;

      //// VALID COUNTER
      logic [$clog2(NEURONS_PER_NP)-1:0] valid_count_r;
    
      // RAM ADDRESSING
      logic [WEIGHT_ADDR_WIDTH-1:0] inf_w_addr;
      logic [THRESHOLD_ADDR_WIDTH-1:0] inf_t_addr;
    
      // RAM CTRL
      logic [P_N-1:0]                           w_wr_en;
      logic [P_N-1:0]                           w_rd_en;
      logic [P_N-1:0][WEIGHT_ADDR_WIDTH-1:0]    w_wr_addr;
      logic [P_N-1:0][WEIGHT_ADDR_WIDTH-1:0]    w_rd_addr;
      logic [P_N-1:0][P_W-1:0]                  w_wr_data;
      logic [P_N-1:0][P_W-1:0]                  w_rd_data;
     
      logic [P_N-1:0]                           t_wr_en;
      logic [P_N-1:0]                           t_rd_en;
      logic [P_N-1:0][THRESHOLD_ADDR_WIDTH-1:0] t_wr_addr;
      logic [P_N-1:0][THRESHOLD_ADDR_WIDTH-1:0] t_rd_addr;
      logic [P_N-1:0][MAX_PC_WIDTH-1:0]         t_wr_data;
      logic [P_N-1:0][MAX_PC_WIDTH-1:0]         t_rd_data;
    
      // NP 
      logic [P_N-1:0] np_valid_out;
    
    
      // COMBO LOGIC
      //// CONFIGURAION
      assign inf_w_addr = neuron_count_r; 
      assign inf_t_addr = neuron_count_r;
    
      always_comb begin
        for (int i=0; i<P_N; i++) begin
          if (config_mode) begin
            w_wr_en[i] = (config_np_id == i) && config_w_we;
            w_wr_addr[i] = config_w_addr;
            w_wr_data[i] = config_w_data;
    
            t_wr_en[i] = (config_np_id == i) && config_t_we;
            t_wr_addr[i] = config_t_addr;
            t_wr_data[i] = config_t_data;
    
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
    
            w_rd_addr[i] = inf_w_addr;
            t_rd_addr[i] = inf_t_addr;
    
            w_rd_en[i] = go_r;
            t_rd_en[i] = go_r;
          end
        end
      end

      //// DATAPATH
    
      // SEQUENTIAL LOGIC
      always_ff @(posedge clk, posedge rst) begin
        if (layer_en) begin
	  // NP CONTROL SIGNALS 
          np_last_r  <= go_r;
	  np_valid_r <= go_r;
          
	  // INPUT BUFFER
	  if (layer_valid_in) begin
	    layer_data_in_r <= layer_data_in;
          end

	  // DONE COUNTER TO SIGNAL LAST NEURON BATCH
	  layer_last <= 1'b0;

	  if (np_valid_out[0]) begin
	    if (valid_count_r == NEURONS_PER_NP-1) begin
	      valid_count_r <= '0;
              layer_last <= 1'b1;
            end else begin
	      valid_count_r <= valid_count_r + 1'b1;
	    end
	  end


	  // OUTPUT BUFFER
	  layer_valid_out_r <= (np_valid_out[0]) ? 1'b1 : 1'b0;
          layer_popcounts_r <= np_popcounts;
	  layer_data_out_r <= np_y;


	  // ADDRESS GENERATOR GO FOR PRE-FETCH
	  if (layer_go_in && layer_ready) begin
            go_r <= 1'b1;
	    done_r <= 1'b0;
	  end

	  // ADDRESS GENERATION
	  if (go_r) begin
            if (neuron_count_r == NEURONS_PER_NP-1) begin
              go_r <= 1'b0;
	      done_r <= 1'b1;
	      neuron_count_r <= '0; 
            end else begin 
              neuron_count_r <= neuron_count_r + 1'b1;

            end
	  end
	end

        if (rst) begin
          go_r <= 1'b0;
          done_r <= 1'b1;
          layer_data_in_r <= '0;
          neuron_count_r <= '0;
          valid_count_r <= '0;
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
	  .en(layer_en),
          .x(layer_data_in_r),
          .w(w_rd_data[i]),
          .threshold(t_rd_data[i]),
          .valid_in(np_valid_r),
          .last(np_last_r),
          .valid_out(np_valid_out[i]),
          .y(np_y[i]),
          .popcount(np_popcounts[i])
        );
    
      end

      // ASSIGN OUTPUTS
      assign layer_go_out = np_valid_out[0];
      assign layer_valid_out = layer_valid_out_r;
      assign layer_popcounts = layer_popcounts_r;
      assign layer_data_out = layer_data_out_r;
      assign layer_ready = done_r;

    end else begin
      // INPUT LAYER (NO NEURONS)

      assign layer_go_out = layer_go_in;
      assign layer_ready = 1'b1;

      always_ff @(posedge clk, posedge rst) begin
	if (layer_go_in && layer_en) begin
	  layer_data_out <= layer_data_in;
          layer_valid_out <= layer_go_in;	
	  layer_last <= layer_go_in;
        end
          
      end
    end 
  endgenerate

endmodule
