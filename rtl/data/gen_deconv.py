import numpy as np

def deconvolution(input_data, weight, bias=None, stride=2, padding=1, output_padding=0):
    input_height, input_width, in_channels = input_data.shape
    out_channels, kernel_height, kernel_width, _ = weight.shape
    out_height = (input_height - 1) * stride + kernel_height - 2 * padding + output_padding
    out_width = (input_width - 1) * stride + kernel_width - 2 * padding + output_padding
    output = np.zeros((out_height, out_width, out_channels), dtype=np.int32)
    for oc in range(out_channels):
        for oh in range(out_height):
            for ow in range(out_width):
                conv_sum = 0
                for ic in range(in_channels):
                    for kh in range(kernel_height-1, -1, -1):
                        for kw in range(kernel_width-1, -1, -1):
                            h_temp = oh - kh + padding
                            w_temp = ow - kw + padding
                            if(ic == 0 and kh == kernel_height-1 and kw == kernel_width-1):
                                clr = 1
                            else:
                                clr = 0
                            if h_temp >= 0 and h_temp % stride == 0 and \
                               w_temp >= 0 and w_temp % stride == 0:
                                ih = h_temp // stride
                                iw = w_temp // stride
                                if 0 <= ih < input_height and 0 <= iw < input_width:
                                    conv_sum += int(input_data[ih, iw, ic]) * int(weight[oc, kh, kw, ic])
                                    string = f"oh {oh}, ow {ow}, kh {kh}, kw {kw}, h_temp {h_temp}, w_temp {w_temp}, ih {ih}, iw {iw}, x {input_data[ih, iw, ic]}, w {weight[oc, kh, kw, ic]}, clr {clr}, sum {conv_sum}"
                                    string += f" ih {ih}, iw {iw}, clr {clr}, x {input_data[ih, iw, ic]}, w {weight[oc, kh, kw, ic]}, sum {conv_sum},"
                                    # print(string)
                if bias is not None:
                    conv_sum += bias[oc]
                output[oh, ow, oc] = conv_sum
    return output


def reshape_weight_for_hardware(weight, P_OCH, P_ICH):
    N_OCH, K, _, N_ICH = weight.shape
    FOLD_O = N_OCH // P_OCH
    FOLD_I = N_ICH // P_ICH
    KK = K * K

    weight_reshaped = weight.reshape(FOLD_O, P_OCH, K, K, FOLD_I, P_ICH)
    weight_reshaped = weight_reshaped.transpose(0, 4, 2, 3, 1, 5)
    weight_reshaped = weight_reshaped.reshape(FOLD_O, FOLD_I, KK, P_OCH, P_ICH)
    
    return weight_reshaped


def save_input_to_mem(input_data, filename, mode, P_ICH, A_BIT=8):
    height, width, channels = input_data.shape
    with open(filename, mode) as f:
        for h in range(height):
            for w in range(width):
                for ch_start in range(0, channels, P_ICH):
                    vec = input_data[h, w, ch_start:ch_start+P_ICH]
                    # Pack P_ICH channels LSB-first as hex
                    hex_str = ''.join([f'{int(val) & 0xFF:02x}' for val in reversed(vec)])
                    f.write(f"{hex_str}\n")
    
    print(f"Saved input (.mem) to {filename}")
    print(f"  Shape: height={height}, width={width}, channels={channels}")


def save_weight_to_mem(weight, filename, mode, P_OCH, P_ICH, W_BIT=8):
    FOLD_O, FOLD_I, KK, _, _ = weight.shape
    with open(filename, mode) as f:
        for fo in range(FOLD_O):
            for fi in range(FOLD_I):
                for kk in range(KK):
                    # Pack P_OCH * P_ICH weights as hex
                    packed = []
                    for o in range(P_OCH):
                        for i in range(P_ICH):
                            val = weight[fo, fi, kk, o, i]
                            # Convert signed to unsigned byte for hex
                            packed.append(int(val) & 0xFF)
                    hex_str = ''.join([f'{v:02x}' for v in reversed(packed)])
                    f.write(f"{hex_str}\n")
    
    print(f"Saved weight (.mem) to {filename}")
    print(f"  Shape: FOLD_O={FOLD_O}, FOLD_I={FOLD_I}, K*K={KK}")


def save_output_to_mem(output, filename, mode, P_OCH, B_BIT=32):
    height, width, channels = output.shape
    
    with open(filename, mode) as f:
        for h in range(height):
            for w in range(width):
                for c in range(channels):
                    val = output[h, w, c]
                    # Convert 32-bit signed to unsigned hex (8 hex digits)
                    f.write(f"{int(val) & 0xFFFFFFFF:08x}\n")
    
    print(f"Saved output (.mem) to {filename}")
    print(f"  Shape: height={height}, width={width}, channels={channels}")


if __name__ == "__main__":
    input_height, input_width = 5, 5
    in_channels = 8
    out_channels = 4
    kernel_size = 3
    stride = 2
    padding = 1
    output_padding = 0
    P_ICH, P_OCH = 4, 2
    Z_NUM, A_BIT, W_BIT, B_BIT = 8, 8, 8, 32

    out_height = (input_height - 1) * stride + kernel_size - 2 * padding + output_padding
    out_width = (input_width - 1) * stride + kernel_size - 2 * padding + output_padding
    input_size = input_height * input_width * in_channels
    input_data = (np.arange(input_size) % 128).astype(np.int8)  # -128-127, int8
    input_data = input_data.reshape(input_height, input_width, in_channels)
    weight_size = out_channels * kernel_size * kernel_size * in_channels
    weight_data = (np.arange(weight_size) % 256).astype(np.int8)  # -128-127, int8
    weight = weight_data.reshape(out_channels, kernel_size, kernel_size, in_channels)
    bias = np.zeros(out_channels, dtype=np.int32)

    print("="*60)
    print("Deconvolution Configuration:")
    print(f"  Input: {input_height}x{input_width}x{in_channels}")
    print(f"  Weight: {out_channels}x{kernel_size}x{kernel_size}x{in_channels}")
    print(f"  Output: {out_height}x{out_width}x{out_channels}")
    print(f"  P_ICH={P_ICH}, P_OCH={P_OCH}")
    print(f"  Kernel={kernel_size}, Stride={stride}, Padding={padding}, Output_Padding={output_padding}")
    print("="*60)

    # Run deconvolution
    output = deconvolution(input_data, weight, bias, stride, padding, output_padding)
    weight_hw = reshape_weight_for_hardware(weight, P_OCH, P_ICH)
    save_input_to_mem(input_data, 'deconv_input.mem', 'w', P_ICH, A_BIT)
    save_input_to_mem(input_data, 'deconv_input.mem', 'a', P_ICH, A_BIT)
    save_weight_to_mem(weight_hw, 'deconv_weight.mem', 'w', P_OCH, P_ICH, W_BIT)
    save_output_to_mem(output, 'deconv_output.mem', 'w', P_OCH, B_BIT)
    save_output_to_mem(output, 'deconv_output.mem', 'a', P_OCH, B_BIT)
    # Save parameters to SystemVerilog header file
    with open('deconv_config.svh', 'w') as f:
        f.write("// Auto-generated configuration file for deconv testbench\n")
        f.write("// Generated by gen_deconv.py\n\n")
        f.write(f"localparam int unsigned P_ICH = {P_ICH};\n")
        f.write(f"localparam int unsigned P_OCH = {P_OCH};\n")
        f.write(f"localparam int unsigned N_ICH = {in_channels};\n")
        f.write(f"localparam int unsigned N_OCH = {out_channels};\n")
        f.write(f"localparam int unsigned K = {kernel_size};\n")
        f.write(f"localparam int unsigned Z_NUM = {Z_NUM};\n")
        f.write(f"localparam int unsigned A_BIT = {A_BIT};\n")
        f.write(f"localparam int unsigned W_BIT = {W_BIT};\n")
        f.write(f"localparam int unsigned B_BIT = {B_BIT};\n")
        f.write(f"localparam int unsigned STRIDE = {stride};\n")
        f.write(f"localparam int unsigned PADDING = {padding};\n")
        f.write(f"localparam int unsigned OUTPUT_PADDING = {output_padding};\n")
        f.write(f"localparam int unsigned IN_H = {input_height};\n")
        f.write(f"localparam int unsigned IN_W = {input_width};\n")
        f.write(f"localparam int unsigned OUT_H = {out_height};\n")
        f.write(f"localparam int unsigned OUT_W = {out_width};\n")
        f.write(f"\n// Derived parameters\n")
        f.write(f"localparam int unsigned FOLD_I = N_ICH / P_ICH;\n")
        f.write(f"localparam int unsigned FOLD_O = N_OCH / P_OCH;\n")
        f.write(f"localparam int unsigned KK = K * K;\n")
        f.write(f"localparam int unsigned WEIGHT_DEPTH = FOLD_O * FOLD_I * KK;\n")
        f.write(f"localparam int unsigned IN_HW = IN_H * IN_W;\n")
        f.write(f"localparam int unsigned OUT_HW = OUT_H * OUT_W;\n")
    print("Saved configuration to deconv_config.svh")


    print("\n" + "="*60)
    print("All files generated successfully!")
    print("="*60)
    print(output)