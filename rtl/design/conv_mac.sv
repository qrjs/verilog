(* use_dsp = "yes" *)
module conv_mac_body #(
    parameter int unsigned A_BIT = 8,
    parameter int unsigned W_BIT = 8,
    parameter int unsigned B_BIT = 32
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    en,
    input  logic        [A_BIT-1:0] x,
    input  logic signed [W_BIT-1:0] w,
    input  logic signed [B_BIT-1:0] acc_in,
    output logic signed [B_BIT-1:0] acc_out
);

    logic signed [B_BIT-1:0] acc_r;
    logic signed [B_BIT-1:0] prod;
    logic signed [B_BIT-1:0] acc;

    assign prod = $signed({1'b0, x}) * w;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_r <= '0;
        end else if (en) begin
            acc_r <= prod + acc_in;
        end
    end
    assign acc_out = acc_r;
endmodule

module conv_mac_tail #(
    parameter int unsigned A_BIT = 8,
    parameter int unsigned W_BIT = 8,
    parameter int unsigned B_BIT = 32
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    en,
    input  logic                    clr,
    input  logic                    dat_vld,
    input  logic        [A_BIT-1:0] x,
    input  logic signed [W_BIT-1:0] w,
    input  logic signed [B_BIT-1:0] acc_in,
    output logic signed [B_BIT-1:0] acc_out
);

    logic signed [B_BIT-1:0] acc_r;
    logic signed [B_BIT-1:0] prod;
    logic signed [B_BIT-1:0] acc;

    assign prod = $signed({1'b0, x}) * w;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_r <= '0;
        end else if (en) begin
            case ({
                clr, dat_vld
            })
                2'b00: acc_r <= acc_r;
                2'b01: acc_r <= acc_in + prod + acc_r;
                2'b10: acc_r <= acc_in;
                2'b11: acc_r <= acc_in + prod;
            endcase
        end
    end
    assign acc_out = acc_r;
endmodule

module conv_mac_array #(
    parameter int unsigned P_ICH = 4,
    parameter int unsigned A_BIT = 8,
    parameter int unsigned W_BIT = 8,
    parameter int unsigned B_BIT = 32
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    en,
    input  logic                    dat_vld,
    input  logic                    clr,
    input  logic        [A_BIT-1:0] x_vec  [P_ICH],
    input  logic signed [W_BIT-1:0] w_vec  [P_ICH],
    output logic signed [B_BIT-1:0] acc
);

    logic        [A_BIT-1:0] x_dly      [  P_ICH];
    logic signed [W_BIT-1:0] w_dly      [  P_ICH];
    logic                    dat_vld_dly[  P_ICH];
    logic                    clr_dly    [  P_ICH];
    logic signed [B_BIT-1:0] mac_cascade[P_ICH+1];

    assign mac_cascade[0] = '0;

    generate
        for (genvar i = 0; i < P_ICH; i++) begin : gen_x_delay
            delayline #(
                .WIDTH(A_BIT),
                .DEPTH(i + 1)
            ) u_x_delayline (
                .clk     (clk),
                .rst_n   (rst_n),
                .en      (en),
                .data_in (x_vec[i]),
                .data_out(x_dly[i])
            );
        end
    endgenerate

    generate
        for (genvar i = 0; i < P_ICH; i++) begin : gen_w_delay
            delayline #(
                .WIDTH(W_BIT),
                .DEPTH(i + 1)
            ) u_w_delayline (
                .clk     (clk),
                .rst_n   (rst_n),
                .en      (en),
                .data_in (w_vec[i]),
                .data_out(w_dly[i])
            );
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 1; i < P_ICH; i++) begin
                clr_dly[i]     <= 1'b0;
                dat_vld_dly[i] <= 1'b0;
            end
        end else if (en) begin
            clr_dly[0]     <= clr;
            dat_vld_dly[0] <= dat_vld;
            for (int i = 1; i < P_ICH; i++) begin
                clr_dly[i]     <= clr_dly[i-1];
                dat_vld_dly[i] <= dat_vld_dly[i-1];
            end
        end
    end

    generate
        for (genvar i = 0; i < P_ICH - 1; i++) begin : gen_mac
            conv_mac_body #(
                .A_BIT(A_BIT),
                .W_BIT(W_BIT),
                .B_BIT(B_BIT)
            ) u_mac_body (
                .clk    (clk),
                .rst_n  (rst_n),
                .en     (en && dat_vld_dly[i]),
                .x      (x_dly[i]),
                .w      (w_dly[i]),
                .acc_in (mac_cascade[i]),
                .acc_out(mac_cascade[i+1])
            );
        end
    endgenerate

    conv_mac_tail #(
        .A_BIT(A_BIT),
        .W_BIT(W_BIT),
        .B_BIT(B_BIT)
    ) u_mac_tail (
        .clk    (clk),
        .rst_n  (rst_n),
        .en     (en),
        .clr    (clr_dly[P_ICH-1]),
        .dat_vld(dat_vld_dly[P_ICH-1]),
        .x      (x_dly[P_ICH-1]),
        .w      (w_dly[P_ICH-1]),
        .acc_in (mac_cascade[P_ICH-1]),
        .acc_out(mac_cascade[P_ICH])
    );

    assign acc = mac_cascade[P_ICH];

endmodule
