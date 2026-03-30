// CREDIT: Greg Stitt, University of Florida
module popcount_p
#(
    parameter int NUM_INPUTS=8,
    parameter int INPUT_WIDTH=1
) (
    input  logic                                      clk,
    input  logic                                      rst,
    input  logic                                      en,
    input  logic [                   INPUT_WIDTH-1:0] inputs[NUM_INPUTS],
    output logic [INPUT_WIDTH+$clog2(NUM_INPUTS)-1:0] sum
);
    generate
        if (INPUT_WIDTH < 1) begin : l_width_validation
            $fatal(1, "ERROR: INPUT_WIDTH must be positive.");
        end

        if (NUM_INPUTS < 1) begin : l_num_inputs_validation
            $fatal(1, "ERROR: Number of inputs must be positive.");
        end else if (NUM_INPUTS == 1) begin : l_base_1_input
            assign sum = inputs[0];        
        end else begin : l_recurse

            localparam int LEFT_TREE_INPUTS = int'($ceil(NUM_INPUTS / 2.0));
            localparam int LEFT_TREE_DEPTH = $clog2(LEFT_TREE_INPUTS);
            logic [INPUT_WIDTH + $clog2(LEFT_TREE_INPUTS)-1:0] left_sum;

            popcount_p #(
                .NUM_INPUTS (LEFT_TREE_INPUTS),
                .INPUT_WIDTH(INPUT_WIDTH)
            ) left_tree (
                .clk   (clk),
                .rst   (rst),
                .en    (en),
                .inputs(inputs[0+:LEFT_TREE_INPUTS]),
                .sum   (left_sum)
            );

            localparam int RIGHT_TREE_INPUTS = NUM_INPUTS / 2;
            localparam int RIGHT_TREE_DEPTH = $clog2(RIGHT_TREE_INPUTS);
            logic [INPUT_WIDTH + $clog2(RIGHT_TREE_INPUTS)-1:0] right_sum, right_sum_unaligned;

            popcount_p #(
                .NUM_INPUTS (RIGHT_TREE_INPUTS),
                .INPUT_WIDTH(INPUT_WIDTH)
            ) right_tree (
                .clk   (clk),
                .rst   (rst),
                .en    (en),
                .inputs(inputs[LEFT_TREE_INPUTS+:RIGHT_TREE_INPUTS]),
                .sum   (right_sum_unaligned)
            );

            localparam int LATENCY_DIFFERENCE = LEFT_TREE_DEPTH - RIGHT_TREE_DEPTH;

            if (LATENCY_DIFFERENCE > 0) begin : l_delay
                logic [$bits(right_sum)-1:0] delay_r[LATENCY_DIFFERENCE];

                always_ff @(posedge clk or posedge rst) begin
                    if (rst) delay_r <= '{default: '0};
                    else if (en) begin
                        delay_r[0] <= right_sum_unaligned;
                        for (int i = 1; i < LATENCY_DIFFERENCE; i++) begin
                            delay_r[i] <= delay_r[i-1];
                        end
                    end
                end

                assign right_sum = delay_r[LATENCY_DIFFERENCE-1];
            end else begin : l_no_delay
                assign right_sum = right_sum_unaligned;
            end

            // Add the two trees together.
            always_ff @(posedge clk or posedge rst) begin
                if (rst) sum <= '0;
                else if (en) sum <= left_sum + right_sum;
            end
        end
    endgenerate
endmodule
