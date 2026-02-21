import sys

with open("ut_conv.sv", "r") as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    new_lines.append(line)
    if "end else if (pipe_en) begin" in line:
        new_lines.append('            $display("T=%0t [dut] in_ready=%b in_valid=%b pipe_en=%b pipe_en_in=%b pipe_en_out=%b out_valid_d=%b out_ready=%b is_fst_fo=%b fo=%0d fi=%0d kk=%0d", $time, in_ready, in_valid, pipe_en, pipe_en_in, pipe_en_out, out_valid_d, out_ready, is_fst_fo, cntr_fo, cntr_fi, cntr_kk);\n')

with open("ut_conv.sv", "w") as f:
    f.writelines(new_lines)
