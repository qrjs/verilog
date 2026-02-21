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

    // 并行乘法：对所有 P_ICH 通道同时求积
    logic signed [B_BIT-1:0] partial_sum;
    always_comb begin
        partial_sum = '0;
        for (int i = 0; i < P_ICH; i++) begin
            partial_sum = partial_sum + ($signed(x_vec[i]) * $signed(w_vec[i]));
        end
    end

    // 跨时钟的累加寄存器
    logic signed [B_BIT-1:0] acc_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_r <= '0;
        end else if (en) begin
            case ({clr, dat_vld})
                2'b00: acc_r <= acc_r;                   // 保持
                2'b01: acc_r <= acc_r + partial_sum;     // 累加
                2'b10: acc_r <= '0;                      // 清零（新输出像素但无数据）
                2'b11: acc_r <= partial_sum;             // 清零并开始新的累加
            endcase
        end
    end

    // 透传输出：当有有效数据时，acc 包含当前拍的 partial_sum（不需要等待下一拍）
    // 这样 out_valid 可以与 dat_vld 同拍触发，无需额外流水延迟
    always_comb begin
        if (dat_vld && en) begin
            if (clr)
                acc = partial_sum;              // 清零并加当前 = just partial_sum
            else
                acc = acc_r + partial_sum;      // 包含当前拍
        end else begin
            acc = acc_r;
        end
    end

endmodule
