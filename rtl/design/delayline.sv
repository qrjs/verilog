module delayline #(
    parameter int unsigned WIDTH = 8,
    parameter int unsigned DEPTH = 1
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic             en,
    input  logic [WIDTH-1:0] data_in,
    output logic [WIDTH-1:0] data_out
);

    generate
        if (DEPTH == 0) begin : gen_no_delay
            assign data_out = data_in;
        end else if (DEPTH == 1) begin : gen_single_delay
            logic [WIDTH-1:0] reg_r;
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    reg_r <= '0;
                end else if (en) begin
                    reg_r <= data_in;
                end
            end
            assign data_out = reg_r;
        end else begin : gen_multi_delay
            logic [WIDTH-1:0] shift_reg[DEPTH];
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    for (int i = 0; i < DEPTH; i++) begin
                        shift_reg[i] <= '0;
                    end
                end else if (en) begin
                    shift_reg[0] <= data_in;
                    for (int i = 1; i < DEPTH; i++) begin
                        shift_reg[i] <= shift_reg[i-1];
                    end
                end
            end
            assign data_out = shift_reg[DEPTH-1];
        end
    endgenerate
endmodule
