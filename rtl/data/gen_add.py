import struct
import random
import os

def gen_data(num_samples=100):
    input_data = []
    final_q_data = []
    output_data = []

    for _ in range(num_samples):
        # Generate 4-bit signed integers (-8 to 7)
        a = random.randint(-8, 7)
        b = random.randint(-8, 7)
        
        # Calculate sum
        res = a + b
        
        # Simulate 4-bit overflow behavior (truncate to 4 bits)
        res_truncated = res & 0xF
        
        input_data.append(a & 0xF)
        final_q_data.append(b & 0xF)
        output_data.append(res_truncated)

    # Write to binary files
    # The testbench reads 32-bit words.
    
    with open('input.bin', 'wb') as f:
        for val in input_data:
            f.write(struct.pack('<I', val)) # Little endian unsigned int
            
    with open('final_q.bin', 'wb') as f:
        for val in final_q_data:
            f.write(struct.pack('<I', val))
            
    with open('output.bin', 'wb') as f:
        for val in output_data:
            f.write(struct.pack('<I', val))

    print(f"Generated {num_samples} samples.")

if __name__ == "__main__":
    gen_data()
