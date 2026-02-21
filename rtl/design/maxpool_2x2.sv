// 2x2 最大池化模块
// 对输入特征图进行 2x2 窗口的最大值池化，stride=2
// 实现：按列对优先顺序输出，正确处理 line buffer 时序
module maxpool_2x2 #(
    parameter int unsigned P_CH  = 4,
    parameter int unsigned N_CH  = 16,
    parameter int unsigned N_IW  = 64,
    parameter int unsigned A_BIT = 8
) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic [P_CH*A_BIT-1:0] in_data,
    input  logic                  in_valid,
    output logic                  in_ready,
    output logic [P_CH*A_BIT-1:0] out_data,
    output logic                  out_valid,
    input  logic                  out_ready
);

    localparam int unsigned FOLD = N_CH / P_CH;
    localparam int unsigned N_OW = N_IW / 2;
    localparam int unsigned LB_DEPTH = N_IW * FOLD;  // 存储整行
    localparam int unsigned LB_AWIDTH = $clog2(LB_DEPTH);

    logic                      cntr_h;
    logic [$clog2(N_IW+1)-1:0] cntr_w;
    logic [$clog2(FOLD+1)-1:0] cntr_f;

    logic                      lb_we;
    logic [     LB_AWIDTH-1:0] lb_waddr;
    logic [    P_CH*A_BIT-1:0] lb_wdata;
    logic                      lb_re;
    logic [     LB_AWIDTH-1:0] lb_raddr;
    logic [    P_CH*A_BIT-1:0] lb_rdata;

    logic [P_CH*A_BIT-1:0] row0_cache [N_IW * FOLD];  // 第一行完整缓存
    logic [P_CH*A_BIT-1:0] row1_cache [N_IW * FOLD];  // 第二行每列缓存（偶数列备用，供奇数列时取用）
    logic [P_CH*A_BIT-1:0] max_result;

    logic pipe_en_in;
    logic pipe_en_out;
    logic pipe_en;

    assign in_ready         = (cntr_h == 1'b0) || ((cntr_h == 1'b1) && out_ready);
    assign pipe_en_in       = in_valid;
    assign pipe_en_out      = out_ready || (cntr_h == 1'b0);
    assign pipe_en          = pipe_en_in && pipe_en_out;

    assign lb_waddr         = cntr_w * FOLD + cntr_f;
    assign lb_raddr         = cntr_w * FOLD + cntr_f;

    // Line buffer：第一行写入，第二行读取
    assign lb_we            = pipe_en && (cntr_h == 1'b0);
    assign lb_re            = pipe_en && (cntr_h == 1'b1);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lb_wdata <= '0;
        end else if (pipe_en && cntr_f == FOLD - 1) begin
            if (cntr_h == 1'b0 && cntr_w[0] == 1'b1) begin
                lb_wdata <= max_result;
            end else if (cntr_h == 1'b0) begin
                lb_wdata <= in_data;
            end else begin
                lb_wdata <= in_data;
            end
        end
    end

    ram #(
        .DWIDTH  (P_CH * A_BIT),
        .AWIDTH  (LB_AWIDTH),
        .MEM_SIZE(LB_DEPTH)
    ) u_line_buf (
        .clk  (clk),
        .we   (lb_we),
        .waddr(lb_waddr),
        .wdata(lb_wdata),
        .re   (lb_re),
        .raddr(lb_raddr),
        .rdata (lb_rdata)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cntr_h <= 0;
            cntr_w <= 0;
            cntr_f <= 0;
        end else if (pipe_en) begin
            if (cntr_f == FOLD - 1) begin
                cntr_f <= 0;
                if (cntr_w == N_IW - 1) begin
                    cntr_w <= 0;
                    cntr_h <= cntr_h + 1;
                end else begin
                    cntr_w <= cntr_w + 1;
                end
            end else begin
                cntr_f <= cntr_f + 1;
            end
        end
    end

    // 缓存第一行数据
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < N_IW * FOLD; i++) begin
                row0_cache[i] <= '0;
            end
        end else if (pipe_en && cntr_h == 1'b0) begin
            row0_cache[cntr_w * FOLD + cntr_f] <= in_data;
        end
    end

    // 缓存第二行（偶数列），查表供奇数列时使用
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < N_IW * FOLD; i++) begin
                row1_cache[i] <= '0;
            end
        end else if (pipe_en && cntr_h == 1'b1) begin
            row1_cache[cntr_w * FOLD + cntr_f] <= in_data;
        end
    end

    // 计算 maxpool
    always_comb begin
        if (cntr_h == 1'b0 && cntr_w[0] == 1'b1) begin
            // 偶数行奇数列：max(当前, 前一偶数列)
            max_result = max_vec(in_data, row0_cache[(cntr_w - 1) * FOLD + cntr_f]);
        end else if (cntr_h == 1'b1 && cntr_w[0] == 1'b1) begin
            // 奇数行奇数列：max(当前行奇列, 当前行偶列, 上一行奇列, 上一行偶列)
            max_result = max4_vec(in_data,
                                  row1_cache[(cntr_w - 1) * FOLD + cntr_f],
                                  row0_cache[cntr_w * FOLD + cntr_f],
                                  row0_cache[(cntr_w - 1) * FOLD + cntr_f]);
        end else begin
            max_result = '0;
        end
    end

    // 输出：奇数行（第二行）奇数列，此时 max4_vec 结果有效
    assign out_valid = pipe_en && (cntr_h == 1'b1) && (cntr_w[0] == 1'b1);
    assign out_data  = max_result;

    function automatic logic [P_CH*A_BIT-1:0] max_vec(input logic [P_CH*A_BIT-1:0] a, input logic [P_CH*A_BIT-1:0] b);
        logic [A_BIT-1:0] a_ch, b_ch;
        for (int i = 0; i < P_CH; i++) begin
            a_ch                     = a[i*A_BIT+:A_BIT];
            b_ch                     = b[i*A_BIT+:A_BIT];
            max_vec[i*A_BIT+:A_BIT] = (a_ch > b_ch) ? a_ch : b_ch;
        end
    endfunction

    function automatic logic [P_CH*A_BIT-1:0] max4_vec(
        input logic [P_CH*A_BIT-1:0] a,
        input logic [P_CH*A_BIT-1:0] b,
        input logic [P_CH*A_BIT-1:0] c,
        input logic [P_CH*A_BIT-1:0] d
    );
        logic [A_BIT-1:0] a_ch, b_ch, c_ch, d_ch;
        logic [A_BIT-1:0] max_ab, max_cd;
        for (int i = 0; i < P_CH; i++) begin
            a_ch = a[i*A_BIT+:A_BIT];
            b_ch = b[i*A_BIT+:A_BIT];
            c_ch = c[i*A_BIT+:A_BIT];
            d_ch = d[i*A_BIT+:A_BIT];
            max_ab = (a_ch > b_ch) ? a_ch : b_ch;
            max_cd = (c_ch > d_ch) ? c_ch : d_ch;
            max4_vec[i*A_BIT+:A_BIT] = (max_ab > max_cd) ? max_ab : max_cd;
        end
    endfunction

endmodule
