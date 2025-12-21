#include <iostream>
#include <vector>
#include "conv.h"
#include "utils.h"

// Parameters
constexpr unsigned N_ICH = 4;
constexpr unsigned N_OCH = 6;
constexpr unsigned N_IH = 5;
constexpr unsigned N_IW = 5;
constexpr unsigned K = 3;
constexpr unsigned P = 1;
constexpr unsigned S = 2; // Stride 2
constexpr unsigned BIT_ACTV = 8;
constexpr unsigned BIT_WGHT = 8;
constexpr unsigned BIT_CONV = 16;

constexpr unsigned P_ICH = 2;
constexpr unsigned P_OCH = 3;

constexpr unsigned N_OH = (N_IH + 2 * P - K) / S + 1;
constexpr unsigned N_OW = (N_IW + 2 * P - K) / S + 1;
constexpr unsigned VEC_LEN = N_OH * N_OW;

constexpr unsigned FOLD_I = N_ICH / P_ICH;
constexpr unsigned FOLD_O = N_OCH / P_OCH;

// Helper to generate input data
template <unsigned DWIDTH>
void gen_ifm(data_stream<DWIDTH>& s_input, std::array<uint32_t, 2> shape) {
    uint32_t size = shape[0] * shape[1];
    for (uint32_t i = 0; i < size; ++i) {
        s_input.write(i % (1 << DWIDTH));
    }
}

// Helper to expand input for conv (Software im2col)
void expand_input(data_stream<BIT_ACTV>& in, data_stream<P_ICH * BIT_ACTV>& out) {
    // Read full input image into buffer
    ap_uint<BIT_ACTV> input_buf[N_IH][N_IW][N_ICH];
    for (unsigned h = 0; h < N_IH; ++h) {
        for (unsigned w = 0; w < N_IW; ++w) {
            for (unsigned c = 0; c < N_ICH; ++c) {
                input_buf[h][w][c] = in.read();
            }
        }
    }

    // Generate sliding windows
    for (unsigned oh = 0; oh < N_OH; ++oh) {
        for (unsigned ow = 0; ow < N_OW; ++ow) {
            for (unsigned fi = 0; fi < FOLD_I; ++fi) {
                for (unsigned kh = 0; kh < K; ++kh) {
                    for (unsigned kw = 0; kw < K; ++kw) {
                        int ih = oh * S + kh - P;
                        int iw = ow * S + kw - P;
                        
                        ap_uint<P_ICH * BIT_ACTV> packed_val = 0;
                        
                        for (unsigned pi = 0; pi < P_ICH; ++pi) {
                            unsigned ic = fi * P_ICH + pi;
                            ap_uint<BIT_ACTV> val = 0;
                            
                            if (ih >= 0 && ih < N_IH && iw >= 0 && iw < N_IW) {
                                val = input_buf[ih][iw][ic];
                            } else {
                                val = 0; // Padding
                            }
                            packed_val(SLICE(BIT_ACTV, pi)) = val;
                        }
                        out.write(packed_val);
                    }
                }
            }
        }
    }
}

int main() {
    // Streams
    data_stream<BIT_ACTV> s_input("s_input");
    data_stream<BIT_ACTV> s_input_golden("s_input_golden");
    
    data_stream<P_ICH * BIT_ACTV> s_input_expanded("s_input_expanded");
    data_stream<P_OCH * BIT_CONV> s_output_packed("s_output_packed");
    data_stream<BIT_CONV> s_output("s_output");
    data_stream<BIT_CONV> s_output_golden("s_output_golden");

    // Generate Input
    std::array<uint32_t, 2> ifm_shape = {N_IH * N_IW, N_ICH};
    gen_ifm<BIT_ACTV>(s_input, ifm_shape);
    gen_ifm<BIT_ACTV>(s_input_golden, ifm_shape);

    // Generate Weights
    ap_int<BIT_WGHT> weight[N_OCH][K*K][N_ICH];
    for(uint32_t oc = 0; oc < N_OCH; ++oc) {
        for(uint32_t k = 0; k < K*K; ++k) {
            for(uint32_t ic = 0; ic < N_ICH; ++ic) {
                weight[oc][k][ic] = (oc + k + ic) % (1 << BIT_WGHT);
            }
        }
    }

    // Reshape Weights for DUT
    ap_uint<P_OCH * P_ICH * BIT_WGHT> weight_reshape[FOLD_O][FOLD_I][K*K];
    for (uint32_t fo = 0; fo < FOLD_O; ++fo) {
        for (uint32_t fi = 0; fi < FOLD_I; ++fi) {
            for (uint32_t k = 0; k < K*K; ++k) {
                ap_uint<P_OCH * P_ICH * BIT_WGHT> w_packed = 0;
                for (uint32_t po = 0; po < P_OCH; ++po) {
                    for (uint32_t pi = 0; pi < P_ICH; ++pi) {
                        uint32_t oc = fo * P_OCH + po;
                        uint32_t ic = fi * P_ICH + pi;
                        ap_int<BIT_WGHT> val = weight[oc][k][ic];
                        w_packed(SLICE(BIT_WGHT, P_ICH * po + pi)) = val;
                    }
                }
                weight_reshape[fo][fi][k] = w_packed;
            }
        }
    }

    // Prepare Input for DUT
    expand_input(s_input, s_input_expanded);

    // Run DUT
    conv<P_ICH, P_OCH, N_ICH, N_OCH, K, BIT_ACTV, BIT_WGHT, BIT_CONV, VEC_LEN>(
        s_input_expanded, s_output_packed, weight_reshape
    );

    // Unpack Output
    reduce_width<P_OCH * BIT_CONV, BIT_CONV, VEC_LEN * FOLD_O>(s_output_packed, s_output);

    // Run Golden
    conv_golden<N_ICH, N_OCH, N_IH, N_IW, K, P, S, BIT_ACTV, BIT_WGHT, BIT_CONV>(
        s_input_golden, s_output_golden, weight
    );

    // Check Results
    auto error_cnt = check_afm<BIT_CONV, N_OH, N_OW, N_OCH>(s_output_golden, s_output, true);

    if(error_cnt > 0) {
        std::cout << "Test Failed! " << error_cnt << " errors" << std::endl;
        return 1;
    } else {
        std::cout << "Test Passed! " << std::endl;
        return 0;
    }
}
