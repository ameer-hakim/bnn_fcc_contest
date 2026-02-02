// AMEER HAKIM
// binary_neuron_p
// Pipelined Binary Neuron Processor for Input Streaming
// Initial Latency (Assuming one beat per neuron) = 2 + clog2(P_W)

module binary_neuron_p #(
  // PARAMETERS
  parameter int P_W = 8,
  parameter int MAX_PC_WIDTH = 32, // $clog2(MAX_NEURON_INPUTS+1) at top level

  // LOCALPARAMS
  localparam int POPCOUNT_LATENCY = $clog2(P_W),
  localparam int THRESHOLD_R_DELAY = POPCOUNT_LATENCY,
  localparam int LAST_DELAY = 1 + POPCOUNT_LATENCY,
  localparam int VALID_IN_DELAY = 1 + POPCOUNT_LATENCY
)(
  // CLK AND RST
  input  logic                    clk,
  input  logic                    rst,

  // INPUTS 
  input  logic [P_W-1:0]          x,
  input  logic [P_W-1:0]          w,
 
  input  logic [MAX_PC_WIDTH-1:0] threshold,
  
  input  logic                    valid_in,
  input  logic                    last,

  // OUTPUTS
  output logic                    valid_out,
  output logic                    y,
  output logic [MAX_PC_WIDTH-1:0] popcount
);
  
  // REGISTERS
  logic [P_W-1:0] xnor_r;
  logic [MAX_PC_WIDTH-1:0] threshold_r, threshold_delayed_r, pc_acc_r, pc_beat_r, popcount_r;
  logic y_r, last_r, last_delayed_r, pc_acc_sel_r,valid_out_r, valid_in_delayed_r;

  // SELECT SIGNALS
  logic pc_acc_sel;
  

  // INTERMEDIATE SIGNALS
  logic y_next;
  logic [MAX_PC_WIDTH-1:0] pc_acc_next, sum;
  logic xnor_unpacked[P_W];
  

  // COMBO LOGIC
  assign y_next = (sum >= threshold_delayed_r) ? 1'b1 : 1'b0;

  assign pc_acc_sel = last_delayed_r;
  assign sum = pc_beat_r + pc_acc_r;
  assign pc_acc_next = ( pc_acc_sel ) ? '0 : sum;
  

  always_comb begin
    for (int i=0; i<P_W; i++) begin
      xnor_unpacked[i] = xnor_r[i];
    end

  end
  
  // STRUCTURAL INSTANTIATION
  popcount_p
  #(
      .NUM_INPUTS(P_W),
      .INPUT_WIDTH(1)
  ) pc_p_recursive (
      .clk(clk),
      .rst(rst),
      .en(1'b1),
      .inputs(xnor_unpacked),
      .sum(pc_beat_r)
  );

  delay #(
      .CYCLES(LAST_DELAY),
      .WIDTH(1)
  ) d_last (
      .clk(clk),
      .rst(rst),
      .en(1'b1),
      .in(last),
      .out(last_delayed_r)
  );

  delay #(
      .CYCLES(THRESHOLD_R_DELAY),
      .WIDTH(MAX_PC_WIDTH)
  ) d_threshold (
      .clk(clk),
      .rst(rst),
      .en(1'b1),
      .in(threshold_r),
      .out(threshold_delayed_r)
  );

  delay #(
      .CYCLES(VALID_IN_DELAY),
      .WIDTH(1)
  ) d_valid_in (
      .clk(clk),
      .rst(rst),
      .en(1'b1),
      .in(valid_in),
      .out(valid_in_delayed_r)
  );

  // SEQUENTIAL LOGIC
  always_ff @(posedge clk, posedge rst) begin
    xnor_r <= (~(x ^ w));

    if (last) threshold_r <= threshold;
    if (valid_in_delayed_r) pc_acc_r <= pc_acc_next;

    y_r <= y_next;
    valid_out_r <= last_delayed_r;
    popcount_r <= sum;

    if ( rst ) begin
        threshold_r <= '0;
        pc_acc_r <= '0;
        valid_out_r <= '0;

    end
  end


  // ASSIGN OUTPUTS
  assign popcount = popcount_r;
  assign valid_out = valid_out_r;
  assign y = y_r;

endmodule
