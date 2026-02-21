import sys

try:
    with open('ut_conv.vcd', 'r') as f:
        # Just grab the first 2000 lines
        lines = [next(f) for _ in range(2000)]
except Exception as e:
    print(f"Error reading file: {e}")
    sys.exit(1)

vars_of_interest = ["in_valid", "in_ready", "out_ready", "pipe_en", "pipe_en_in", "pipe_en_out", "out_valid_d", "is_fst_fo"]
var_map = {}

print("Looking for variables:")
for line in lines:
    if line.startswith('$var'):
        parts = line.split()
        if len(parts) >= 4:
            v_type, size, symbol, name = parts[1], parts[2], parts[3], parts[4]
            if name in vars_of_interest:
                var_map[symbol] = name
                print(f"  {name} -> {symbol}")

print("\nSignal trace:")
current_time = "0"
values = {sym: 'x' for sym in var_map.keys()}
for line in lines:
    line = line.strip()
    if line.startswith('#'):
        current_time = line[1:]
    elif line and line[0] in ['0', '1', 'x', 'z'] and len(line) > 1:
        val = line[0]
        sym = line[1:]
        if sym in var_map:
            values[sym] = val
            print(f"Time {current_time}: {var_map[sym]} = {val}")
