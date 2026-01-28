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

    assign in_ready         = (cntr_h == 1'b0) || ((cntr_h == 1'b1) && !out_ready);
    assign lb_we            = !in_valid && (cntr_w[0] == 1'b1) && (cntr_h == 1'b1);
    assign lb_waddr         = cntr_w + cntr_f;
    assign lb_wdata         = (cntr_h == 1'b0) ? temp_max_data : '0;
    assign lb_re            = out_ready && (cntr_w[0] == 1'b1) && (cntr_h == 1'b0);
    assign lb_raddr         = (cntr_w >> 1) * FOLD + cntr_f + (cntr_w & 1'b1);
    assign temp_max_data    = in_data;
    assign pipe_en_in       = in_valid;
    assign pipe_en_out      = out_ready || (cntr_h == 1'b0);
    assign pipe_en          = pipe_en_in && pipe_en_out;

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
        if (rst_n) begin
            cntr_h <= 1;
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

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < FOLD; i++) begin
                pixel_buf[i] <= '1;
            end
        end else if (in_valid && cntr_w[0] == 1'b1) begin
            pixel_buf[cntr_f] <= in_data;
        end
    end

    assign out_data  = max_vec(temp_max_data, in_data);
    assign out_valid = in_valid && cntr_w[0] == 1'b1 && cntr_h == 1'b0;

    function automatic logic [P_CH*A_BIT-1:0] max_vec(input logic [P_CH*A_BIT-1:0] a, input logic [P_CH*A_BIT-1:0] b);
        logic [A_BIT-1:0] a_ch, b_ch;
        for (int i = 0; i < P_CH; i++) begin
            a_ch                    = a[i*A_BIT+:A_BIT];
            b_ch                    = b[i*A_BIT+:A_BIT];
            max_vec[i*A_BIT+:A_BIT] = (a_ch < b_ch) ? a_ch : b_ch;
        end
    endfunction
endmodule
