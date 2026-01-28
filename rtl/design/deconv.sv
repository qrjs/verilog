module deconv #(
    parameter int unsigned P_ICH      = 4,
    parameter int unsigned P_OCH      = 4,
    parameter int unsigned N_ICH      = 16,
    parameter int unsigned N_OCH      = 16,
    parameter int unsigned N_IH       = 8,
    parameter int unsigned N_IW       = 8,
    parameter int unsigned K          = 3,
    parameter int unsigned P          = 1,
    parameter int unsigned S          = 2,
    parameter int unsigned O_P        = 0,
    parameter int unsigned A_BIT      = 8,
    parameter int unsigned W_BIT      = 8,
    parameter int unsigned B_BIT      = 32,
    parameter string       W_FILE     = "",
    parameter              W_ROM_TYPE = "block"
) (
    input logic clk,
    input logic rst_n,

    input  logic [P_ICH*A_BIT-1:0] in_data,
    input  logic                   in_valid,
    output logic                   in_ready,

    output logic [P_OCH*B_BIT-1:0] out_data,
    output logic                   out_valid,
    input  logic                   out_ready
);

    localparam int unsigned N_OH = (N_IH - 1) * S + K - 2 * P + O_P;
    localparam int unsigned N_OW = (N_IW - 1) * S + K - 2 * P + O_P;
    localparam int unsigned FOLD_I = N_ICH / P_ICH;
    localparam int unsigned FOLD_O = N_OCH / P_OCH;
    localparam int unsigned KK = K * K;
    localparam int unsigned WEIGHT_DEPTH = FOLD_O * FOLD_I * KK;
    localparam int unsigned LB_H = S + 1;
    localparam int unsigned LB_DEPTH = LB_H * N_IW * FOLD_I;
    localparam int unsigned LB_AWIDTH = $clog2(LB_DEPTH);

    logic [$clog2(WEIGHT_DEPTH)-1:0] weight_addr;
    logic [   P_OCH*P_ICH*W_BIT-1:0] weight_data;
    rom #(
        .DWIDTH(P_OCH * P_ICH * W_BIT),
        .AWIDTH($clog2(WEIGHT_DEPTH)),
        .MEM_SIZE(WEIGHT_DEPTH),
        .INIT_FILE(W_FILE),
        .ROM_TYPE(W_ROM_TYPE)
    ) u_weight_rom (
        .clk  (clk),
        .ce0  (out_ready),
        .addr0(weight_addr),
        .q0   (weight_data)
    );


    logic                   line_buffer_we;
    logic [  LB_AWIDTH-1:0] line_buffer_waddr;
    logic [P_ICH*A_BIT-1:0] line_buffer_wdata;
    logic                   line_buffer_re;
    logic [  LB_AWIDTH-1:0] line_buffer_raddr;
    logic [P_ICH*A_BIT-1:0] line_buffer_rdata;

    ram #(
        .DWIDTH(P_ICH * A_BIT),
        .AWIDTH(LB_AWIDTH),
        .MEM_SIZE(LB_DEPTH),
        .RAM_STYLE("ultra")
    ) u_line_buffer (
        .clk  (clk),
        .we   (line_buffer_we),
        .waddr(line_buffer_waddr),
        .wdata(line_buffer_wdata),
        .re   (line_buffer_re),
        .raddr(line_buffer_raddr),
        .rdata(line_buffer_rdata)
    );

    typedef enum logic [1:0] {
        ST_INIT,
        ST_PROC
    } state_t;
    state_t                             state;

    logic        [  $clog2(LB_H+1)-1:0] cntr_init_h;
    logic        [  $clog2(N_IW+1)-1:0] cntr_init_w;
    logic        [$clog2(FOLD_I+1)-1:0] cntr_init_fi;
    logic        [  $clog2(N_OH+1)-1:0] cntr_oh;
    logic        [  $clog2(N_OW+1)-1:0] cntr_ow;
    logic        [$clog2(FOLD_O+1)-1:0] cntr_fo;
    logic        [     $clog2(K+1)-1:0] cntr_kh;
    logic        [     $clog2(K+1)-1:0] cntr_kw;
    logic        [$clog2(FOLD_I+1)-1:0] cntr_fi;
    logic        [  $clog2(N_IH+1)-1:0] ih_to_read;
    logic        [    $clog2(N_IW)-1:0] iw_to_read;
    logic                               pipe_en_in;
    logic                               pipe_en_out;
    logic                               pipe_en;
    logic                               need_read_input;
    logic        [ $clog2(N_IH*N_IW):0] read_input_cnt;
    logic                               read_input_done;
    logic                               mac_array_data_vld;
    logic                               is_fst_kh_kw_fi;
    logic                               is_lst_kh_kw_fi;
    logic signed [           B_BIT-1:0] acc                   [  P_OCH];
    logic signed [  $clog2(N_OH+K)+1:0] h_temp;
    logic signed [  $clog2(N_OW+K)+1:0] w_temp;
    logic signed [    $clog2(N_IH)+1:0] ih;
    logic signed [    $clog2(N_IW)+1:0] iw;
    logic                               valid_pos;

    assign h_temp = cntr_oh - cntr_kh + P;
    assign w_temp = cntr_ow - cntr_kw + P;
    assign ih = h_temp / S;
    assign iw = w_temp / S;
    assign iw_to_read = cntr_ow / S;
    assign valid_pos = (h_temp >= 0) && ((h_temp % S == 0) || (w_temp % S == 0)) && 
                       (w_temp >= 0) &&
                       (ih >= 0) && (ih < N_IH) && 
                       (iw >= 0) && (iw < N_IW);
    assign need_read_input = (cntr_oh % S == 0) && (cntr_ow % S == 0) && 
                             (cntr_kh == K - 1) && (cntr_kw == K - 1) && 
                             (cntr_fo == 0) && (ih_to_read < N_IH);
    assign pipe_en_in = need_read_input ? in_valid : 1'b1;
    assign pipe_en_out = out_ready;
    assign pipe_en = pipe_en_in && pipe_en_out;
    assign in_ready = ((state == ST_INIT) || (state == ST_PROC && need_read_input && out_ready));
    assign weight_addr = (cntr_fo * KK * FOLD_I) + (cntr_fi * KK) + (cntr_kw * K + cntr_kh);
    assign line_buffer_we = ((state == ST_INIT) && in_valid) || ((state == ST_PROC) && need_read_input && in_valid);
    assign line_buffer_waddr = (state == ST_INIT) ? 
                               (cntr_init_h * N_IW * FOLD_I + cntr_init_w * FOLD_I + cntr_init_fi) :
                               ((ih_to_read % LB_H) * N_IW * FOLD_I + iw_to_read * FOLD_I + cntr_fi);
    assign line_buffer_wdata = in_data;
    assign line_buffer_re = out_ready && (state == ST_PROC);
    assign line_buffer_raddr = ((ih % LB_H) * N_IW * FOLD_I + iw * FOLD_I + cntr_fi) + (cntr_kh & 1'b1);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_input_cnt <= 0;
        end else if (pipe_en && need_read_input && in_valid) begin
            if (read_input_cnt == (N_IH * N_IW) - 1) begin
                read_input_cnt <= 0;
            end else begin
                read_input_cnt <= read_input_cnt + 1;
            end
        end
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_INIT;
            cntr_init_h  <= 0;
            cntr_init_w  <= 0;
            cntr_init_fi <= 0;
            cntr_oh      <= 0;
            cntr_ow      <= 0;
            cntr_fo      <= 0;
            cntr_kh      <= K - 1;
            cntr_kw      <= K - 1;
            cntr_fi      <= 0;
            ih_to_read   <= S;
        end else begin
            case (state)
                ST_INIT: begin
                    if (in_valid) begin
                        if (cntr_init_fi == FOLD_I - 1) begin
                            cntr_init_fi <= 0;
                            if (cntr_init_w == N_IW - 1) begin
                                cntr_init_w <= 0;
                                if (cntr_init_h == S - 1) begin
                                    state <= ST_PROC;
                                end else begin
                                    cntr_init_h <= cntr_init_h + 1;
                                end
                            end else begin
                                cntr_init_w <= cntr_init_w + 1;
                            end
                        end else begin
                            cntr_init_fi <= cntr_init_fi + 1;
                        end
                    end
                end

                ST_PROC: begin
                    if (pipe_en) begin
                        if (need_read_input && in_valid) begin
                            if ((iw_to_read == N_IW - 1) && (cntr_fi == FOLD_I - 1)) begin
                                ih_to_read <= ih_to_read + 1;
                            end
                        end
                        if (cntr_fi == FOLD_I - 1) begin
                            cntr_fi <= 0;
                            if (cntr_kw == 0) begin
                                cntr_kw <= K - 1;
                                if (cntr_kh == 0) begin
                                    cntr_kh <= K - 1;
                                    if (cntr_fo == FOLD_O - 1) begin
                                        cntr_fo <= 0;
                                        if (cntr_ow == N_OW - 1) begin
                                            cntr_ow <= 0;
                                            if (cntr_oh == N_OH - 1) begin
                                                state        <= ST_INIT;
                                                cntr_oh      <= 0;
                                                cntr_init_h  <= 0;
                                                cntr_init_w  <= 0;
                                                cntr_init_fi <= 0;
                                                ih_to_read   <= S;
                                            end else begin
                                                cntr_oh <= cntr_oh + 1;
                                            end
                                        end else begin
                                            cntr_ow <= cntr_ow + 1;
                                        end
                                    end else begin
                                        cntr_fo <= cntr_fo + 1;
                                    end
                                end else begin
                                    cntr_kh <= cntr_kh - 1;
                                end
                            end else begin
                                cntr_kw <= cntr_kw - 1;
                            end
                        end else begin
                            cntr_fi <= cntr_fi + 1;
                        end
                    end
                end
            endcase
        end
    end

    assign is_fst_kh_kw_fi    = (cntr_kh == K - 1) && (cntr_kw == K - 1) && (cntr_fi == 0);
    assign is_lst_kh_kw_fi    = (cntr_kh == 0) && (cntr_kw == 0) && (cntr_fi == FOLD_I - 1);
    assign mac_array_data_vld = valid_pos && (state == ST_PROC);

    logic        [A_BIT-1:0] x_vec[P_ICH];
    logic signed [W_BIT-1:0] w_vec[P_OCH] [P_ICH];
    always_comb begin
        for (int i = 0; i < P_ICH; i++) begin
            x_vec[i] = line_buffer_rdata[i*A_BIT+:A_BIT];
        end
    end

    always_comb begin
        for (int o = 0; o < P_OCH; o++) begin
            for (int i = 0; i < P_ICH; i++) begin
                w_vec[o][i] = weight_data[(P_ICH*o+i)*W_BIT+:W_BIT];
            end
        end
    end

    generate
        for (genvar o = 0; o < P_OCH; o++) begin : gen_mac_array
            mac_array #(
                .P_ICH(P_ICH),
                .A_BIT(A_BIT),
                .W_BIT(W_BIT),
                .B_BIT(B_BIT)
            ) u_mac_array (
                .clk    (clk),
                .rst_n  (rst_n),
                .en     (out_ready),
                .dat_vld(mac_array_data_vld),
                .clr    (is_fst_kh_kw_fi),
                .x_vec  (x_vec),
                .w_vec  (w_vec[o]),
                .acc    (acc[o])
            );
        end
    endgenerate

    always_comb begin
        for (int o = 0; o < P_OCH; o++) begin
            out_data[o*B_BIT+:B_BIT] = acc[P_OCH-1-o];
        end
    end
    assign out_valid = is_lst_kh_kw_fi;
endmodule
