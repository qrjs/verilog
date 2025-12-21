import numpy as np
import os

def im2col(input_data, kernel_size, stride=1, padding=0):
    input_height, input_width, channels = input_data.shape
    out_height = (input_height + 2 * padding - kernel_size) // stride + 1
    out_width  = (input_width  + 2 * padding - kernel_size) // stride + 1
    output_data = np.zeros((out_height * out_width, kernel_size * kernel_size * channels), dtype=np.int32)

    for oh in range(out_height):
        for ow in range(out_width):
            for c in range(channels):
                for kh in range(kernel_size):
                    for kw in range(kernel_size):
                        ih = oh * stride - padding + kh
                        iw = ow * stride - padding + kw
                        if 0 <= ih < input_height and 0 <= iw < input_width:
                            output_data[oh * out_width + ow, kh * kernel_size * channels + kw * channels + c] = input_data[ih, iw, c]
                        else:
                            output_data[oh * out_width + ow, kh * kernel_size * channels + kw * channels + c] = 0
    return output_data.reshape(out_height * out_width, -1)

def convolution(input_data, weight, bias=None, stride=1, padding=0):
    input_height, input_width, in_channels = input_data.shape
    out_channels, kernel_height, kernel_width, _ = weight.shape

    out_height = (input_height + 2 * padding - kernel_height) // stride + 1
    out_width = (input_width + 2 * padding - kernel_width) // stride + 1
    output = np.zeros((out_height, out_width, out_channels), dtype=np.int32)

    for oc in range(out_channels):
        for oh in range(out_height):
            for ow in range(out_width):
                conv_sum = 0
                for ic in range(in_channels):
                    for kh in range(kernel_height):
                        for kw in range(kernel_width):
                            ih = oh * stride - padding + kh
                            iw = ow * stride - padding + kw
                            if 0 <= ih < input_height and 0 <= iw < input_width:
                                conv_sum += int(input_data[ih, iw, ic]) * int(weight[oc, kh, kw, ic])
                if bias is not None:
                    conv_sum += bias[oc]
                output[oh, ow, oc] = conv_sum
    return output

def convolution_with_im2col(input_data, weight, bias=None, stride=1, padding=0):
    input_height, input_width, in_channels = input_data.shape
    out_channels, kernel_height, kernel_width, _ = weight.shape

    im2col_matrix = im2col(input_data, kernel_height, stride, padding)
    weight_matrix = weight.reshape(out_channels, -1)
    print(im2col_matrix, weight_matrix)
    out_height = (input_height + 2 * padding - kernel_height) // stride + 1
    out_width = (input_width + 2 * padding - kernel_width) // stride + 1
    
    output = im2col_matrix @ weight_matrix.T

    # Add bias if provided
    if bias is not None:
        output += bias
    
    # Reshape to final output format
    return output.reshape(out_height, out_width, out_channels)

def reshape_im2col_for_hardware(im2col_data, kernel_size, in_channels, P_ICH):
    im2col_reshaped = im2col_data.reshape(-1, kernel_size, kernel_size, in_channels // P_ICH, P_ICH)
    im2col_reshaped = im2col_reshaped.transpose(0, 3, 1, 2, 4)

    return im2col_reshaped.reshape(-1, kernel_size * kernel_size * in_channels)

def reshape_weight_for_hardware(weight, P_OCH, P_ICH):
    N_OCH, K, _, N_ICH = weight.shape
    FOLD_O = N_OCH // P_OCH
    FOLD_I = N_ICH // P_ICH
    KK = K * K
    print(weight)
    # Reshape: (N_OCH, K, K, N_ICH) -> (FOLD_O, P_OCH, K, K, FOLD_I, P_ICH)
    weight_reshaped = weight.reshape(FOLD_O, P_OCH, K, K, FOLD_I, P_ICH)
    print(weight_reshaped)
    
    # Transpose to: (FOLD_O, FOLD_I, K, K, P_OCH, P_ICH)
    weight_reshaped = weight_reshaped.transpose(0, 4, 2, 3, 1, 5)
    print(weight_reshaped)
    # Reshape to: (FOLD_O, FOLD_I, K*K, P_OCH, P_ICH)
    weight_reshaped = weight_reshaped.reshape(FOLD_O, FOLD_I, KK, P_OCH, P_ICH)
    print(weight_reshaped)
    return weight_reshaped


def save_input_to_mem(input_data, filename, mode, P_ICH, A_BIT=8):
    height, width, channels = input_data.shape

    with open(filename, mode) as f:
        for h in range(height):
            for w in range(width):
                for ch_start in range(0, channels, P_ICH):
                    # Pack P_ICH channels into one hex line
                    hex_values = []
                    for ch in range(ch_start, min(ch_start + P_ICH, channels)):
                        val = int(input_data[h, w, ch])
                        hex_values.append(f"{val:02x}")
                    # Write in little-endian order (reverse)
                    f.write(''.join(reversed(hex_values)) + '\n')
    
    print(f"Saved input (dat) to {filename}")
    print(f"  Format: hex values for $readmemh")


def save_im2col_to_mem(im2col_data, filename, mode, P_ICH, A_BIT=8):
    n_vec, total_ch = im2col_data.shape
    with open(filename, mode) as f:
        for vec_idx in range(n_vec):
            for ch_start in range(0, total_ch, P_ICH):
                # Pack P_ICH values into one hex line
                hex_values = []
                for ch in range(ch_start, min(ch_start + P_ICH, total_ch)):
                    val = int(im2col_data[vec_idx, ch])
                    hex_values.append(f"{val:02x}")
                # Write in little-endian order (reverse)
                f.write(''.join(reversed(hex_values)) + '\n')
    
    print(f"Saved im2col (dat) to {filename}")
    print(f"  Format: hex values for $readmemh")

def save_weight_to_mem(weight, filename, mode, P_OCH, P_ICH, W_BIT=8):
    FOLD_O, FOLD_I, KK, _, _ = weight.shape
    with open(filename, mode) as f:
        for fo in range(FOLD_O):
            for fi in range(FOLD_I):
                for kk in range(KK):
                    # Pack P_OCH*P_ICH weights into one hex line
                    hex_values = []
                    for o in range(P_OCH):
                        for i in range(P_ICH):
                            val = int(weight[fo, fi, kk, o, i])
                            # Convert to unsigned representation for hex
                            if val < 0:
                                val = val & ((1 << W_BIT) - 1)
                            hex_values.append(f"{val:02x}")
                    # Write in little-endian order (reverse for readmemh)
                    f.write(''.join(reversed(hex_values)) + '\n')
    
    print(f"Saved weight (dat) to {filename}")
    print(f"  Format: hex values for $readmemh")

def save_output_to_mem(output, filename, mode, B_BIT=32):
    height, width, channels = output.shape
    with open(filename, mode) as f:
        for h in range(height):
            for w in range(width):
                for c in range(channels):
                    val = int(output[h, w, c])
                    # Convert to unsigned representation for hex
                    if val < 0:
                        val = val & ((1 << B_BIT) - 1)
                    # Format as hex with appropriate width (B_BIT/4 hex digits)
                    hex_width = B_BIT // 4
                    f.write(f"{val:0{hex_width}x}\n")
    
    print(f"Saved output (dat) to {filename}")
    print(f"  Format: hex values for $readmemh")


if __name__ == "__main__":
    # Configuration
    height, width, in_channels = 5, 5, 8
    out_channels = 4
    P_ICH, P_OCH = 4, 2
    kernel_size, stride, padding = 3, 1, 1
    A_BIT, W_BIT, B_BIT = 8, 8, 32

    # Generate test data using arange (0-127 range)
    # Input data
    input_size = height * width * in_channels
    input_data = (np.arange(input_size) % 128).astype(np.uint8)  # 0-127, uint8
    input_data = input_data.reshape(height, width, in_channels)

    # Weight data
    weight_size = out_channels * kernel_size * kernel_size * in_channels
    weight_data = (np.arange(weight_size) % 128).astype(np.uint8)  # 0-127, uint8
    weight = weight_data.reshape(out_channels, kernel_size, kernel_size, in_channels)

    bias = np.zeros(out_channels, dtype=np.int32)

    print("="*60)
    print("Configuration:")
    print(f"  Input: {height}x{width}x{in_channels}")
    print(f"  Weight: {out_channels}x{kernel_size}x{kernel_size}x{in_channels}")
    print(f"  P_ICH={P_ICH}, P_OCH={P_OCH}")
    print(f"  Kernel={kernel_size}, Stride={stride}, Padding={padding}")
    print("="*60)

    im2col_data = im2col(input_data, kernel_size, stride, padding)
    im2col_reshaped = reshape_im2col_for_hardware(im2col_data, kernel_size, in_channels, P_ICH)
    output_im2col = convolution_with_im2col(input_data, weight, bias, stride, padding)
    output_golden = convolution(input_data, weight, bias, stride, padding)

    max_diff = np.max(np.abs(output_im2col - output_golden))
    mean_diff = np.mean(np.abs(output_im2col - output_golden))
    print(f"\nOutput shape: {output_im2col.shape}")
    print(f"Max difference: {max_diff:.6f}")
    print(f"Mean difference: {mean_diff:.6f}")
    print(f"Results match: {np.allclose(output_im2col, output_golden, rtol=1e-5, atol=1e-6)}")

    # Reshape weight for hardware
    print("\n" + "="*60)
    print("Reshaping weight for hardware...")
    weight_hw = reshape_weight_for_hardware(weight, P_OCH, P_ICH)
    print(f"Weight hardware shape: {weight_hw.shape}")
    print(f"  (FOLD_O, FOLD_I, K*K, P_OCH, P_ICH) = {weight_hw.shape}")

    # Create data directory if it doesn't exist
    os.makedirs('.', exist_ok=True)

    # Save to binary files
    print("\n" + "="*60)
    print("Saving data to binary and text files...")
    
    # Save parameters to SystemVerilog header file
    with open('conv_config.svh', 'w') as f:
        f.write("// Auto-generated configuration file for conv testbench\n")
        f.write("// Generated by gen_conv.py\n\n")
        f.write(f"localparam int unsigned P_ICH = {P_ICH};\n")
        f.write(f"localparam int unsigned P_OCH = {P_OCH};\n")
        f.write(f"localparam int unsigned N_ICH = {in_channels};\n")
        f.write(f"localparam int unsigned N_OCH = {out_channels};\n")
        f.write(f"localparam int unsigned K = {kernel_size};\n")
        f.write(f"localparam int unsigned A_BIT = {A_BIT};\n")
        f.write(f"localparam int unsigned W_BIT = {W_BIT};\n")
        f.write(f"localparam int unsigned B_BIT = {B_BIT};\n")
        f.write(f"localparam int unsigned N_HW = {output_im2col.shape[1] * output_im2col.shape[2]};\n")
        f.write(f"\n// Im2col parameters\n")
        f.write(f"localparam int unsigned N_IH = {height};\n")
        f.write(f"localparam int unsigned N_IW = {width};\n")
        f.write(f"localparam int unsigned STRIDE = {stride};\n")
        f.write(f"localparam int unsigned PAD = {padding};\n")
        f.write(f"\n// Derived parameters\n")
        f.write(f"localparam int unsigned FOLD_I = N_ICH / P_ICH;\n")
        f.write(f"localparam int unsigned FOLD_O = N_OCH / P_OCH;\n")
        f.write(f"localparam int unsigned KK = K * K;\n")
        f.write(f"localparam int unsigned WEIGHT_DEPTH = FOLD_O * FOLD_I * KK;\n")
    print("Saved configuration to conv_config.svh")
    
    # Save input
    save_input_to_mem(input_data, 'conv_input.mem', 'w', P_ICH, A_BIT)
    save_input_to_mem(input_data, 'conv_input.mem', 'a', P_ICH, A_BIT)
    save_im2col_to_mem(im2col_reshaped, 'conv_im2col.mem', 'w', P_ICH, A_BIT)
    save_im2col_to_mem(im2col_reshaped, 'conv_im2col.mem', 'a', P_ICH, A_BIT)
    save_weight_to_mem(weight_hw, 'conv_weight.mem', 'w', P_OCH, P_ICH, W_BIT)
    save_output_to_mem(output_im2col, 'conv_output.mem', 'w', B_BIT)
    save_output_to_mem(output_im2col, 'conv_output.mem', 'a', B_BIT)

    print(f"Saved output (dat) to conv_output.mem")