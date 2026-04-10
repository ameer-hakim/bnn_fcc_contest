`ifndef BNN_FCC_PKG_SVH
`define BNN_FCC_PKG_SVH

  // MAX PW FUNCTION
  function automatic int get_max_pw (
    input int TOTAL_LAYERS,
    input int TOPOLOGY[],
    input int NP_CYCLES
  );
    int max_val = 0;
  
    for (int i = 1; i < TOTAL_LAYERS; i++) begin
      int pw = TOPOLOGY[i-1] / NP_CYCLES;
  
      if (pw > max_val) begin
        max_val = pw;
      end
    end
  
    return max_val;
  endfunction

  // GET P_N FOR A LAYER
  function automatic int get_pn(
    input TOPOLOGY[],
    input int LAYER,
    input int NP_CYCLES
  );

    if (LAYER == 0) return 0;
    else return (TOPOLOGY[LAYER] / NP_CYCLES);

  endfunction

`endif
