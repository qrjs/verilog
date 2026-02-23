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
    localparam int unsigned LB_DEPTH = N_OW * FOLD;
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
    logic [    P_CH*A_BIT-1:0] pixel_buf        [FOLD];
    logic                      pipe_en_in;
    logic                      pipe_en_out;
    logic                      pipe_en;
    logic [    P_CH*A_BIT-1:0] temp_max_data;

    // out_valid_d1 同步于 pipe_en_d1。由于有1拍延迟，我们需要一个停等机制，或者使用 valid-ready 流水线通用结构。
    // 更简单的办法：不需要打拍 out_valid，只需要提前1拍读 RAM，但是让 RAM 读地址和 in_ready / pipe_en 相关解耦。
    // 但原版骨架是完全无阻塞固定延时的。既然有打一拍流水，如果 out_valid_d1=1 且 out_ready=0，我们必须冻结打拍寄存器。
    
    // 我们引入 pipeline stall 信号
    logic stall;
    logic out_valid_d1;
    // 如果当前有输出，且下游未准备好，则整个流水线必须暂停！
    assign stall            = out_valid_d1 && !out_ready;
    
    // in_ready 现在必须额外由 stall 信号控制
    // 如果 stall 为 1，说明下游堵住，流水线不能进新数据
    // 另外还需要看当前周期是否要发出输出 (当前周期 cntr_w[0]==1 且 cntr_h==1 时，如果有新数据进来，下一周期必定有输出)
    assign in_ready         = !stall && (out_ready || !(cntr_h == 1'b1 && cntr_w[0] == 1'b1));
    assign pipe_en          = in_valid && in_ready && !stall;
    assign temp_max_data    = max_vec(in_data, pixel_buf[cntr_f]);

    // 第一行奇数列（每2x2池化窗口右侧算完后），写入线缓存
    assign lb_we            = pipe_en && (cntr_h == 1'b0) && (cntr_w[0] == 1'b1);
    assign lb_waddr         = (cntr_w >> 1) * FOLD + cntr_f;
    assign lb_wdata         = temp_max_data;

    // 第二行，奇数列当拍提取时，同步发起 RAM 读请求
    assign lb_re            = pipe_en && (cntr_h == 1'b1) && (cntr_w[0] == 1'b1); 
    assign lb_raddr         = (cntr_w >> 1) * FOLD + cntr_f;

    // Instantiate RAM completely naturally here below
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
        .rdata(lb_rdata)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cntr_h <= 0;
            cntr_w <= 0;
            cntr_f <= 0;
        end else begin
            if (pipe_en) begin
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
    end

    // == 增加一拍流水线打拍 == //
    logic [P_CH*A_BIT-1:0] temp_max_data_d1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            temp_max_data_d1 <= 0;
            out_valid_d1     <= 0;
        end else if (!stall) begin 
            // 只有当没有阻塞时，流水线才往前走
            if (pipe_en) begin
                temp_max_data_d1 <= temp_max_data;
                out_valid_d1     <= (cntr_h == 1'b1) && (cntr_w[0] == 1'b1);
            end else begin
                out_valid_d1     <= 0;
            end
        end
        // 当 stall 为 1 时，保持 temp_max_data_d1 和 out_valid_d1 不变，从而维持输出不变
    end

    // 最终输出：用延迟了一拍的水平最大值，和刚出炉的 SRAM 读数据比较
    assign out_data  = max_vec(temp_max_data_d1, lb_rdata);
    assign out_valid = out_valid_d1;

    /* 
    always_ff @(posedge clk) begin
        if (pipe_en || out_valid_d1) begin
            $display("[Maxpool Debug] Time=%0d, pipe_en=%b, cntr_h=%0d, cntr_w=%0d, cntr_f=%0d | temp_max=%x | temp_max_d1=%x | lb_raddr=%0d(re=%b, data=%x) | lb_waddr=%0d(we=%b, data=%x) | out_valid=%b, out_data=%x", 
                $time, pipe_en, cntr_h, cntr_w, cntr_f, temp_max_data, temp_max_data_d1, lb_raddr, lb_re, lb_rdata, lb_waddr, lb_we, lb_wdata, out_valid_d1, out_data);
        end
    end
    */

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < FOLD; i++) begin
                pixel_buf[i] <= '1;
            end
        end else if (pipe_en && cntr_w[0] == 1'b0) begin
            pixel_buf[cntr_f] <= in_data;
        end
    end

    function automatic logic [P_CH*A_BIT-1:0] max_vec(input logic [P_CH*A_BIT-1:0] a, input logic [P_CH*A_BIT-1:0] b);
        logic [A_BIT-1:0] a_ch, b_ch;
        for (int i = 0; i < P_CH; i++) begin
            a_ch                    = a[i*A_BIT+:A_BIT];
            b_ch                    = b[i*A_BIT+:A_BIT];
            max_vec[i*A_BIT+:A_BIT] = (a_ch > b_ch) ? a_ch : b_ch;
        end
    endfunction
endmodule
