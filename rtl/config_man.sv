// AMEER HAKIM
// config_man.sv
// Coniguration manager for the bnn.sv module. To be implemented within the
// bnn_fcc.sv top-level module
//
module config_man #(
  // PARAMETERS
 
  // LOCALPARAMS
)(
  // CLK AND RST
  input logic clk,
  input logic rst,

);


  typdef enum logic [1:0] {
    HEADER_0,
    HEADER_1,
    PAYLOAD,  
    default = 'X
  } state_t;

  state_t state_r, next_state;
 

  always_ff @(posedge clk, posedge rst) begin



  end

endmodule
