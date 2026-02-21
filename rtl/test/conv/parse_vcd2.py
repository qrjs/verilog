import sys

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
    if "$var" in line:
        parts = line.split()
        if len(parts) >= 5:
            name = parts[4]
            symbol = parts[3]
            if name in vars_of_interest:
                var_map[symbol] = name
                print(f"  {name} -> {symbol}")

print("\nSignal trace (first 100 changes):")
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
            if changes > 100: break
