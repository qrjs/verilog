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
    logic                                   is_fst_fo;
    logic                                   mac_array_data_vld;

    logic                                   is_fst_kk_fi;
    logic                                   is_lst_kk_fi;
    logic                                   line_buffer_we;
    logic        [           LB_AWIDTH-1:0] line_buffer_waddr;
    logic        [         P_ICH*A_BIT-1:0] line_buffer_wdata;
    logic                                   line_buffer_re;
    logic        [           LB_AWIDTH-1:0] line_buffer_raddr;
    logic        [         P_ICH*A_BIT-1:0] line_buffer_rdata;
    logic        [$clog2(WEIGHT_DEPTH)-1:0] weight_addr;
    logic        [   P_OCH*P_ICH*W_BIT-1:0] weight_data;

    rom #(
        .DWIDTH(P_OCH * P_ICH * W_BIT),
        .AWIDTH($clog2(WEIGHT_DEPTH)),
        .MEM_SIZE(WEIGHT_DEPTH),
        .INIT_FILE(W_FILE)
    ) u_weight_rom (
        .clk  (clk),
        .ce0  (pipe_en_out),
        .addr0(weight_addr),
        .q0   (weight_data)
    );

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

    assign is_fst_fo            = (cntr_fo == 0);
    assign is_fst_kk_fi         = (cntr_kk == 0) && (cntr_fi == 0);
    assign is_lst_kk_fi         = (cntr_kk == KK - 1) && (cntr_fi == FOLD_I - 1) && pipe_en_in;
    logic                                   out_valid_d;
    assign pipe_en_in           = is_fst_fo ? in_valid : 1'b1;
    assign pipe_en_out          = out_ready || (!out_valid_d);
    assign pipe_en              = pipe_en_in && pipe_en_out;
    // in_ready 仅在 is_fst_fo 时有效：fo=1 时 DUT 从 LB 读取，无需新输入
    assign in_ready             = is_fst_fo && pipe_en_out;
    assign weight_addr          = (cntr_fo * KK * FOLD_I) + cntr_fi * KK + cntr_kk;
    assign line_buffer_we       = is_fst_fo && in_valid;
    assign line_buffer_waddr    = cntr_fi * KK + cntr_kk;
    assign line_buffer_wdata    = in_data;
    assign line_buffer_re    = !is_fst_fo && pipe_en_out;  // 暂停时不读 LB，防止 rdata 超前
    assign line_buffer_raddr = cntr_fi * KK + cntr_kk;

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

    assign mac_array_data_vld = (is_fst_fo ? in_valid : 1'b1);

    // 延迟寄存器: 对齐 weight ROM 1拍读取延迟
    logic [P_ICH*A_BIT-1:0] in_data_d;   // in_data 延迟 1 拍
    logic [A_BIT-1:0]        x_mac [P_ICH];  // 送入 MAC 的输入（非压缩数组与端口匹配）
    logic signed [W_BIT-1:0] w_vec [P_OCH][P_ICH];
    logic                    dat_vld_d;
    logic                    clr_d;
    logic                    dat_vld_mac;
    logic                    clr_mac;
    logic                    is_fst_fo_d;  // is_fst_fo 延迟 1 拍

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_data_d   <= '0;
            dat_vld_d   <= 1'b0;
            clr_d       <= 1'b0;
            is_fst_fo_d <= 1'b1;
        end else if (pipe_en_out) begin
            in_data_d   <= in_data;             // 缓存当前输入，与 ROM 对齐
            dat_vld_d   <= mac_array_data_vld;  // 延迟有效标志
            clr_d       <= is_fst_kk_fi;        // 延迟清零信号
            is_fst_fo_d <= is_fst_fo;           // 延迟流向选择
        end
    end

    // in_buf_d: 使用延迟后的 is_fst_fo_d 选择数据源
    // fo=0: 用 in_data_d (对齐 ROM 1拍延迟)
    // fo=1: 用 lb_rdata  (干 1拍读取延迟，在 fo=0 过渡的一拍后仍指向正确的 LB 数据)
    always_comb begin
        for (int i = 0; i < P_ICH; i++) begin
            x_mac[i] = is_fst_fo_d
                       ? in_data_d[i*A_BIT+:A_BIT]
                       : line_buffer_rdata[i*A_BIT+:A_BIT];
        end
    end
    assign dat_vld_mac = dat_vld_d;
    assign clr_mac     = clr_d;

    always_comb begin
        for (int o = 0; o < P_OCH; o++) begin
            for (int i = 0; i < P_ICH; i++) begin
                w_vec[o][i] = weight_data[(P_ICH*o+i)*W_BIT+:W_BIT];
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
                .dat_vld(dat_vld_mac),
                .clr    (clr_mac),
                .x_vec  (x_mac),
                .w_vec  (w_vec[o]),
                .acc    (acc[o])
            );
        end
    endgenerate

    // 输出有效延迟 1 拍，与 x_vec_d/weight_data 流水对齐
    // conv_mac_array 输出 acc 为组合逻辑（含当前拍 partial_sum），无需额外等待
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid_d <= 1'b0;
        end else if (pipe_en_out) begin
            if (out_valid_d && out_ready) begin
                out_valid_d <= is_lst_kk_fi; // or 0 depending on next state
            end else begin
                out_valid_d <= is_lst_kk_fi;
            end
        end else if (out_valid_d && out_ready) begin
            out_valid_d <= 1'b0;
        end
    end

    assign out_valid = out_valid_d;

    always_comb begin
        for (int o = 0; o < P_OCH; o++) begin
            out_data[o*B_BIT+:B_BIT] = acc[o];
        end
    end
endmodule
