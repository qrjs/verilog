#include <iostream>
#include <vector>
#include <algorithm>
#include "maxpool.h"
#include "utils.h"

// Define parameters
constexpr unsigned N_BATCH = 1;
constexpr unsigned N_IH = 4; // Input Height
constexpr unsigned N_IW = 4; // Input Width
constexpr unsigned N_CH = 4; // Channels
constexpr unsigned P_CH = 2; // Parallel Channels
constexpr unsigned BIT = 8;  // Bit width

// Derived parameters
constexpr unsigned N_OH = N_IH / 2;
constexpr unsigned N_OW = N_IW / 2;
constexpr unsigned FOLD = N_CH / P_CH;

template <unsigned DWIDTH>
void gen_ifm(data_stream<DWIDTH>& s_input, unsigned size) {
    for (unsigned i = 0; i < size; ++i) {
        s_input.write(rand() % (1 << DWIDTH));
    }
}

template <unsigned N_CH, unsigned N_IH, unsigned N_IW, unsigned BIT>
void maxpool_golden(data_stream<BIT>& in, data_stream<BIT>& out) {
    std::vector<ap_uint<BIT>> input_data(N_IH * N_IW * N_CH);
    for(unsigned i=0; i<N_IH * N_IW * N_CH; ++i) {
        input_data[i] = in.read();
    }
    
    for(unsigned r = 0; r < N_IH; r += 2) {
        for(unsigned c = 0; c < N_IW; c += 2) {
            for(unsigned ch = 0; ch < N_CH; ++ch) {
                ap_uint<BIT> v00 = input_data[(r * N_IW + c) * N_CH + ch];
                ap_uint<BIT> v01 = input_data[(r * N_IW + c + 1) * N_CH + ch];
                ap_uint<BIT> v10 = input_data[((r + 1) * N_IW + c) * N_CH + ch];
                ap_uint<BIT> v11 = input_data[((r + 1) * N_IW + c + 1) * N_CH + ch];
                
                ap_uint<BIT> max_v = v00;
                if(v01 > max_v) max_v = v01;
                if(v10 > max_v) max_v = v10;
                if(v11 > max_v) max_v = v11;
                
                out.write(max_v);
            }
        }
    }
}

int main() {
    // Streams
    data_stream<BIT> s_input("s_input");
    data_stream<BIT> s_input_golden("s_input_golden");
    
    data_stream<P_CH * BIT> s_input_packed("s_input_packed");
    data_stream<P_CH * BIT> s_output_packed("s_output_packed");
    
    data_stream<BIT> s_output("s_output");
    data_stream<BIT> s_output_golden("s_output_golden");

    // Generate Data
    unsigned input_size = N_BATCH * N_IH * N_IW * N_CH;
    
    // Fill s_input and s_input_golden with same data
    for (unsigned i = 0; i < input_size; ++i) {
        ap_uint<BIT> val = i % (1 << BIT);
        s_input.write(val);
        s_input_golden.write(val);
    }

    // Pack input for DUT
    expand_width<BIT, P_CH * BIT, N_BATCH * N_IH * N_IW * N_CH>(s_input, s_input_packed);

    // Run DUT
    // Template: P_CH, N_OCH, A_BIT, N_OH, N_OW, N_BATCH
    // Note: maxpool_2x2 N_OH and N_OW are INPUT dimensions.
    maxpool_2x2<P_CH, N_CH, BIT, N_IH, N_IW, N_BATCH>(s_input_packed, s_output_packed);

    // Unpack output
    unsigned output_size = N_BATCH * N_OH * N_OW * N_CH;
    reduce_width<P_CH * BIT, BIT, N_BATCH * N_OH * N_OW * FOLD>(s_output_packed, s_output);

    // Run Golden
    maxpool_golden<N_CH, N_IH, N_IW, BIT>(s_input_golden, s_output_golden);

    // Check results
    // check_afm expects H, W, C.
    // Output shape is (N_OH, N_OW, N_CH)
    auto error_cnt = check_afm<BIT, N_OH, N_OW, N_CH>(s_output_golden, s_output, true);

    if(error_cnt > 0) {
        std::cout << "Test Failed! " << error_cnt << " errors" << std::endl;
        return 1;
    } else {
        std::cout << "Test Passed! " << std::endl;
        return 0;
    }
}
