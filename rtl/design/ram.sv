`timescale 1 ns / 1 ps

module ram #(
    parameter DWIDTH   = 32,
    parameter AWIDTH   = 10,
    parameter MEM_SIZE = 1024
) (
    input  logic              clk,
    input  logic              we,
    input  logic [AWIDTH-1:0] waddr,
    input  logic [DWIDTH-1:0] wdata,
    input  logic              re,
    input  logic [AWIDTH-1:0] raddr,
    output logic [DWIDTH-1:0] rdata
);

    (* ram_style = "block" *)
    logic [DWIDTH-1:0] ram[0:MEM_SIZE-1];

    always_ff @(posedge clk) begin
        if (we) begin
            ram[waddr] <= wdata;
        end
    end

    always_ff @(posedge clk) begin
        if (re) begin
            rdata <= ram[raddr];
        end
    end

endmodule
