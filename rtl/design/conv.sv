module conv #(
    parameter int unsigned P_ICH      = 4,
    parameter int unsigned P_OCH      = 4,
    parameter int unsigned N_ICH      = 16,
    parameter int unsigned N_OCH      = 16,
    parameter int unsigned K          = 3,
    parameter int unsigned A_BIT      = 8,
    parameter int unsigned W_BIT      = 8,
    parameter int unsigned B_BIT      = 32,
    parameter int unsigned N_HW       = 64,
    parameter string       W_FILE     = "",
    parameter              W_ROM_TYPE = "block"
) (
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic [P_ICH*A_BIT-1:0] in_data,
    input  logic                   in_valid,
    output logic                   in_ready,
    output logic [P_OCH*B_BIT-1:0] out_data,
    output logic                   out_valid,
    input  logic                   out_ready
);

    localparam int unsigned FOLD_I = N_ICH / P_ICH;
    localparam int unsigned FOLD_O = N_OCH / P_OCH;
    localparam int unsigned KK = K * K;
    localparam int unsigned WEIGHT_DEPTH = FOLD_O * FOLD_I * KK;
    localparam int unsigned LB_DEPTH = FOLD_I * KK;
    localparam int unsigned LB_AWIDTH = $clog2(LB_DEPTH);

    logic signed [               B_BIT-1:0] acc                   [  P_OCH];
    logic        [      $clog2(N_HW+1)-1:0] cntr_hw;
    logic        [    $clog2(FOLD_O+1)-1:0] cntr_fo;
    logic        [    $clog2(FOLD_I+1)-1:0] cntr_fi;
    logic        [        $clog2(KK+1)-1:0] cntr_kk;
    logic                                   pipe_en_in;
    logic                                   pipe_en_out;
    logic                                   is_fst_fo_d0;
    logic                                   is_fst_fo_d1;
    logic                                   is_fst_fo_d2;
    logic                                   mac_array_data_vld_d1;
    logic                                   mac_array_data_vld_d2;
    logic        [         P_ICH*A_BIT-1:0] in_data_d1;
    logic        [         P_ICH*A_BIT-1:0] in_data_d2;
    logic        [         P_ICH*A_BIT-1:0] in_buf_d2;
    logic                                   is_fst_kk_fi_d0;
    logic                                   is_fst_kk_fi_d1;
    logic                                   is_fst_kk_fi_d2;
    logic                                   is_lst_kk_fi_d0;
    logic                                   is_lst_kk_fi_d1;
    logic                                   is_lst_kk_fi_d2;
    logic                                   is_lst_kk_fi_dly      [P_ICH+1];
    logic                                   line_buffer_we;
    logic        [           LB_AWIDTH-1:0] line_buffer_waddr;
    logic        [         P_ICH*A_BIT-1:0] line_buffer_wdata;
    logic                                   line_buffer_re;
    logic        [           LB_AWIDTH-1:0] line_buffer_raddr_d0;
    logic        [           LB_AWIDTH-1:0] line_buffer_raddr_d1;
    logic        [         P_ICH*A_BIT-1:0] line_buffer_rdata_d2;
    logic        [$clog2(WEIGHT_DEPTH)-1:0] weight_addr_d0;
    logic        [   P_OCH*P_ICH*W_BIT-1:0] weight_data_d1;
    logic        [   P_OCH*P_ICH*W_BIT-1:0] weight_data_d2;

    rom #(
        .DWIDTH(P_OCH * P_ICH * W_BIT),
        .AWIDTH($clog2(WEIGHT_DEPTH)),
        .MEM_SIZE(WEIGHT_DEPTH),
        .INIT_FILE(W_FILE),
        .ROM_TYPE(W_ROM_TYPE)
    ) u_weight_rom (
        .clk  (clk),
        .ce0  (out_ready),
        .addr0(weight_addr_d0),
        .q0   (weight_data_d1)
    );

    ram #(
        .DWIDTH  (P_ICH * A_BIT),
        .AWIDTH  (LB_AWIDTH),
        .MEM_SIZE(LB_DEPTH)
    ) u_line_buffer (
        .clk  (clk),
        .we   (line_buffer_we),
        .waddr(line_buffer_waddr),
        .wdata(line_buffer_wdata),
        .re   (line_buffer_re),
        .raddr(line_buffer_raddr_d1),
        .rdata(line_buffer_rdata_d2)
    );

    assign is_fst_fo_d0         = (cntr_fo == 0);
    assign is_fst_kk_fi_d0      = (cntr_kk == 0) && (cntr_fi == 0);
    assign is_lst_kk_fi_d0      = (cntr_kk == KK - 1) && (cntr_fi == FOLD_I - 1) && pipe_en_in;
    assign pipe_en_in           = is_fst_fo_d0 ? in_valid : 1'b1;
    assign pipe_en_out          = out_ready;
    assign pipe_en              = pipe_en_in && pipe_en_out;
    assign in_ready             = is_fst_fo_d0 && out_ready;
    assign weight_addr_d0       = (cntr_fo * KK * FOLD_I) + cntr_fi * KK + cntr_kk;
    assign line_buffer_we       = is_fst_fo_d0 && in_valid && out_ready;
    assign line_buffer_waddr    = cntr_fi * KK + cntr_kk;
    assign line_buffer_wdata    = in_data;
    assign line_buffer_re       = out_ready;
    assign line_buffer_raddr_d0 = cntr_fi * KK + cntr_kk;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cntr_hw <= 0;
            cntr_fo <= 0;
            cntr_fi <= 0;
            cntr_kk <= 0;
        end else if (pipe_en) begin
            if (cntr_kk == KK - 1) begin
                cntr_kk <= 0;
                if (cntr_fi == FOLD_I - 1) begin
                    cntr_fi <= 0;
                    if (cntr_fo == FOLD_O - 1) begin
                        cntr_fo <= 0;
                        if (cntr_hw == N_HW - 1) begin
                            cntr_hw <= 0;
                        end else begin
                            cntr_hw <= cntr_hw + 1;
                        end
                    end else begin
                        cntr_fo <= cntr_fo + 1;
                    end
                end else begin
                    cntr_fi <= cntr_fi + 1;
                end
            end else begin
                cntr_kk <= cntr_kk + 1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            line_buffer_raddr_d1  <= 'd0;
            in_data_d1            <= 'd0;
            in_data_d2            <= 'd0;
            is_fst_fo_d1          <= 'd0;
            is_fst_fo_d2          <= 'd0;
            is_fst_kk_fi_d1       <= 'd0;
            is_fst_kk_fi_d2       <= 'd0;
            is_lst_kk_fi_d1       <= 'd0;
            is_lst_kk_fi_d2       <= 'd0;
            mac_array_data_vld_d1 <= 'd0;
            mac_array_data_vld_d2 <= 'd0;
            weight_data_d2        <= 'd0;
        end else if (pipe_en_out) begin
            line_buffer_raddr_d1  <= line_buffer_raddr_d0;
            in_data_d1            <= in_data;
            in_data_d2            <= in_data_d1;
            is_fst_fo_d1          <= is_fst_fo_d0;
            is_fst_fo_d2          <= is_fst_fo_d1;
            is_fst_kk_fi_d1       <= is_fst_kk_fi_d0;
            is_fst_kk_fi_d2       <= is_fst_kk_fi_d1;
            is_lst_kk_fi_d1       <= is_lst_kk_fi_d0;
            is_lst_kk_fi_d2       <= is_lst_kk_fi_d1;
            mac_array_data_vld_d1 <= (is_fst_fo_d0 ? in_valid : 1'b1);
            mac_array_data_vld_d2 <= mac_array_data_vld_d1;
            weight_data_d2        <= weight_data_d1;
        end
    end
    assign in_buf_d2 = is_fst_fo_d2 ? in_data_d2 : line_buffer_rdata_d2;
    logic        [A_BIT-1:0] x_vec[P_ICH];
    logic signed [W_BIT-1:0] w_vec[P_OCH] [P_ICH];
    always_comb begin
        for (int i = 0; i < P_ICH; i++) begin
            x_vec[i] = in_buf_d2[i*A_BIT+:A_BIT];
        end
    end

    always_comb begin
        for (int o = 0; o < P_OCH; o++) begin
            for (int i = 0; i < P_ICH; i++) begin
                w_vec[o][i] = weight_data_d2[(P_ICH*o+i)*W_BIT+:W_BIT];
            end
        end
    end

    generate
        for (genvar o = 0; o < P_OCH; o++) begin : gen_mac_array
            conv_mac_array #(
                .P_ICH(P_ICH),
                .A_BIT(A_BIT),
                .W_BIT(W_BIT),
                .B_BIT(B_BIT)
            ) u_mac_array (
                .clk    (clk),
                .rst_n  (rst_n),
                .en     (pipe_en_out),
                .dat_vld(mac_array_data_vld_d2),
                .clr    (is_fst_kk_fi_d2),
                .x_vec  (x_vec),
                .w_vec  (w_vec[o]),
                .acc    (acc[o])
            );
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < P_ICH + 1; i++) begin
                is_lst_kk_fi_dly[i] <= 1'b0;
            end
        end else if (pipe_en_out) begin
            is_lst_kk_fi_dly[0] <= is_lst_kk_fi_d2;
            for (int i = 1; i < P_ICH + 1; i++) begin
                is_lst_kk_fi_dly[i] <= is_lst_kk_fi_dly[i-1];
            end
        end
    end

    assign out_valid = is_lst_kk_fi_dly[P_ICH];

    always_comb begin
        for (int o = 0; o < P_OCH; o++) begin
            out_data[o*B_BIT+:B_BIT] = acc[o];
        end
    end
endmodule
