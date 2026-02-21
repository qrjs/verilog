import os
import subprocess

# We will just write a small testbench patch to print signals and re-run.
with open("ut_conv.sv", "r") as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    new_lines.append(line)
    if "end else if (pipe_en) begin" in line:
        new_lines.append('            $display("T=%0t pipe_en=1 fo=%0d fi=%0d kk=%0d", $time, cntr_fo, cntr_fi, cntr_kk);\n')

with open("ut_conv.sv", "w") as f:
    f.writelines(new_lines)
