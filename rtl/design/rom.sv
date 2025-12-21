// ==============================================================
// ROM Module
// Configurable ROM with external initialization file
// ==============================================================
`timescale 1 ns / 1 ps

module rom #(
    parameter DWIDTH = 24,
    parameter AWIDTH = 6,
    parameter MEM_SIZE = 54,
    parameter INIT_FILE = "rom_init.mem",
    parameter ROM_TYPE = "block"
) (
    input  logic              clk,
    input  logic              ce0,
    input  logic [AWIDTH-1:0] addr0,
    output logic [DWIDTH-1:0] q0
);

    (* rom_style = ROM_TYPE *)
    reg [DWIDTH-1:0] ram[0:MEM_SIZE-1];

    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, ram);
        end
    end

    always_ff @(posedge clk) begin
        if (ce0) begin
            q0 <= ram[addr0];
        end
    end

endmodule
