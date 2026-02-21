import sys
import re

try:
    with open('ut_conv.vcd', 'r') as f:
        lines = f.readlines()
except Exception as e:
    print(f"Error reading file: {e}")
    sys.exit(1)

vars_of_interest = ["in_valid", "in_ready", "out_ready", "pipe_en", "pipe_en_in", "pipe_en_out", "out_valid_d", "is_fst_fo"]
var_map = {}

print("Found variables:")
for line in lines:
    if "$var" in line and 'wire' in line:
        # Format: $var wire 1 % in_valid $end
        m = re.search(r'\$var\s+wire\s+\d+\s+(\S+)\s+(\S+)\s+\$end', line)
        if m:
            symbol = m.group(1)
            name = m.group(2)
            if name in vars_of_interest:
                var_map[symbol] = name
                print(f"  {name} -> {symbol}")

print("\nSignal trace (first 200 changes):")
changes = 0
current_time = "0"
for line in lines:
    line = line.strip()
    if line.startswith('#'):
        current_time = line[1:]
    elif line and line[0] in ['0', '1', 'x', 'z', 'b']:
        if line[0] == 'b':
            parts = line.split(' ')
            if len(parts) == 2:
                val = parts[0]
                sym = parts[1]
            else: continue
        else:
            val = line[0]
            sym = line[1:]
            
        if sym in var_map:
            print(f"Time {current_time}: {var_map[sym]} = {val}")
            changes += 1
            if changes > 200: break
