`timescale 1ns / 1ps

module maxpool_2x2 #(
    parameter int unsigned P_CH  = 4,
    parameter int unsigned N_CH  = 16,
    parameter int unsigned N_IH  = 32,
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
    localparam int unsigned MEM_DEPTH = (N_IW / 2) * FOLD;
    localparam int unsigned MEM_AWIDTH = (MEM_DEPTH > 1) ? $clog2(MEM_DEPTH) : 1;

    // Signals
    logic [P_CH*A_BIT-1:0] pixel_buf [FOLD];
    logic [MEM_AWIDTH-1:0] ram_addr;
    logic                  ram_we;
    logic                  ram_re;
    logic [P_CH*A_BIT-1:0] ram_wdata;
    logic [P_CH*A_BIT-1:0] ram_rdata;

    // Counters
    logic [$clog2(FOLD > 1 ? FOLD : 2)-1:0] cnt_fold;
    logic [$clog2(N_IW)-1:0]                cnt_col;
    logic [$clog2(N_IH)-1:0]                cnt_row;

    logic is_row_odd;
    logic is_col_odd;
    logic handshake;
    logic end_of_row;

    assign handshake  = in_valid && in_ready;
    assign is_row_odd = cnt_row[0];
    assign is_col_odd = cnt_col[0];
    assign end_of_row = (cnt_fold == FOLD - 1) && (cnt_col == N_IW - 1);

    // Helper function for max
    function automatic logic [P_CH*A_BIT-1:0] vec_max(
        input logic [P_CH*A_BIT-1:0] val1,
        input logic [P_CH*A_BIT-1:0] val2
    );
        logic [P_CH*A_BIT-1:0] res;
        for (int i = 0; i < P_CH; i++) begin
            logic [A_BIT-1:0] v1, v2, mx;
            v1 = val1[i*A_BIT +: A_BIT];
            v2 = val2[i*A_BIT +: A_BIT];
            mx = (v1 > v2) ? v1 : v2;
            res[i*A_BIT +: A_BIT] = mx;
        end
        return res;
    endfunction

    // RAM Instantiation
    ram #(
        .DWIDTH  (P_CH * A_BIT),
        .AWIDTH  (MEM_AWIDTH),
        .MEM_SIZE(MEM_DEPTH)
    ) u_line_buf (
        .clk  (clk),
        .we   (ram_we),
        .waddr(ram_addr),
        .wdata(ram_wdata),
        .re   (ram_re),
        .raddr(ram_addr),
        .rdata(ram_rdata)
    );

    // Logic
    logic [P_CH*A_BIT-1:0] current_h_max;
    assign current_h_max = vec_max(pixel_buf[cnt_fold], in_data);

    // Output Logic
    assign out_valid = handshake && is_row_odd && is_col_odd;
    assign out_data  = vec_max(ram_rdata, current_h_max);

    // Ready Logic
    // If we are in the output phase (Row Odd, Col Odd), we depend on out_ready.
    // Otherwise, we are ready to accept input.
    assign in_ready = (is_row_odd && is_col_odd) ? out_ready : 1'b1;

    // RAM Control
    // Write: Row Even, Col Odd.
    // Read:  Row Odd, Col Even.
    assign ram_we    = handshake && (!is_row_odd) && is_col_odd;
    assign ram_re    = handshake && (is_row_odd) && (!is_col_odd);
    assign ram_wdata = current_h_max;

    // Counters and State Update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_fold <= '0;
            cnt_col  <= '0;
            cnt_row  <= '0;
            ram_addr <= '0;
        end else begin
            if (handshake) begin
                // RAM Address Update
                if (end_of_row) begin
                    ram_addr <= '0;
                end else if ((!is_row_odd && is_col_odd) || (is_row_odd && !is_col_odd)) begin
                    ram_addr <= ram_addr + 1;
                end

                // Counters
                if (cnt_fold == FOLD - 1) begin
                    cnt_fold <= '0;
                    if (cnt_col == N_IW - 1) begin
                        cnt_col <= '0;
                        if (cnt_row == N_IH - 1) begin
                            cnt_row <= '0;
                        end else begin
                            cnt_row <= cnt_row + 1;
                        end
                    end else begin
                        cnt_col <= cnt_col + 1;
                    end
                end else begin
                    cnt_fold <= cnt_fold + 1;
                end
            end
        end
    end

    // Pixel Buffer Update
    // Store in_data when Col is Even
    always_ff @(posedge clk) begin
        if (handshake && !is_col_odd) begin
            pixel_buf[cnt_fold] <= in_data;
        end
    end

endmodule