// AXI-Stream 加法器模块
// 支持多通道并行加法运算，使用握手协议控制数据流
module add #(
    parameter P_CH  = 4,              // 并行通道数
    parameter A_BIT = 8               // 每个通道的数据位宽
) (
    input  logic                  clk,
    input  logic                  rst_n,
    // 输入通道 1
    input  logic                  in1_valid,
    output logic                  in1_ready,
    input  logic [P_CH*A_BIT-1:0] in1_data,
    // 输入通道 2
    input  logic                  in2_valid,
    output logic                  in2_ready,
    input  logic [P_CH*A_BIT-1:0] in2_data,
    // 输出通道
    output logic                  out_valid,
    input  logic                  out_ready,
    output logic [P_CH*A_BIT-1:0] out_data
);

    logic                  pipe_valid;
    logic [P_CH*A_BIT-1:0] pipe_data;
    logic [P_CH*A_BIT-1:0] calc_result;
    logic                  can_accept;

    // 判断是否可以接受新数据：pipeline 为空或输出已准备好
    // 【Bug 修复说明】: 只有在内部没有挂起的数据，或者下游(out_ready)准备好接收当前数据时，才可以载入新数据
    assign can_accept = !pipe_valid || out_ready;

    // 反压信号：只有当可以接受数据，且两个输入都有效时，才准备好
    // 【Bug 修复说明】: AXI-Stream 多路同步握手的核心！不能让两路独立握手。
    // 如果只有 in1 有效而 in2 无效，独立握手会导致 in1 被“吃掉”（移入流水线）而 in2 没有跟随。
    // 因此 in1_ready 必须等待 in2_valid 也就绪，反之亦然。两个 ready 必须同步拉高。
    assign in1_ready = can_accept && in2_valid;
    assign in2_ready = can_accept && in1_valid;

    // 并行加法运算
    always_comb begin
        for (int i = 0; i < P_CH; i++) begin
            logic signed [A_BIT-1:0] x1;
            logic signed [A_BIT-1:0] x2;
            logic signed [A_BIT-1:0] sum;

            // 【Bug 修复说明】: 修复有符号数位切片（Bit-slicing）提取丢失符号位的问题。
            // 在 Verilog 中，即便左侧变量 (x1, x2) 声明为 signed，
            // 直接将大数据位切片 in1_data[i*A_BIT+:A_BIT] 赋值过去时，综合工具会将其视为无符号数。
            // 必须使用 $signed() 显式转换为有符号数，否则输入负数时加法逻辑会出错（负数被当做极大正数）。
            x1  = $signed(in1_data[i*A_BIT+:A_BIT]);
            x2  = $signed(in2_data[i*A_BIT+:A_BIT]);
            sum = x1 + x2;

            calc_result[i*A_BIT+:A_BIT] = sum;
        end
    end

    // 流水线寄存器
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pipe_valid <= 1'b0;
            pipe_data  <= '0;
        end else begin
            // 当两个输入都有效且可以接受数据时，写入 pipeline
            if (in1_valid && in2_valid && can_accept) begin
                pipe_valid <= 1'b1;
                pipe_data  <= calc_result;
            end else if (pipe_valid && out_ready) begin
                // 输出被消费后，清除 valid
                pipe_valid <= 1'b0;
            end
        end
    end

    assign out_valid = pipe_valid;
    assign out_data  = pipe_data;

endmodule
