#include <sys/time.h>
#include "deconv.h"
#include "utils.h"

// Missing definitions
constexpr unsigned BIT_ACTV = 8;
constexpr unsigned BIT_WGHT = 8;
constexpr unsigned BIT_CONV = 16;

template <unsigned DWIDTH>
void gen_ifm(data_stream<DWIDTH>& s_input, std::array<uint32_t, 2> shape) {
    uint32_t size = shape[0] * shape[1];
    for (uint32_t i = 0; i < size; ++i) {
        s_input.write(i % (1 << DWIDTH));
    }
}

int main()
{
    // Test parameters
    constexpr uint32_t N_ICH = 4;
    constexpr uint32_t N_OCH = 6;
    constexpr uint32_t N_IH = 5;
    constexpr uint32_t N_IW = 5;
    constexpr uint32_t K = 3;
    constexpr uint32_t P = 1;
    constexpr uint32_t S = 2;
    constexpr uint32_t O_P = 1;
    constexpr uint32_t N_OH = (N_IH - 1) * S + K - 2 * P + O_P;
    constexpr uint32_t N_OW = (N_IW - 1) * S + K - 2 * P + O_P;
    constexpr uint32_t VEC_LEN = N_OH * N_OW;
    constexpr uint32_t P_ICH = 2;
    constexpr uint32_t P_OCH = 3;
    constexpr uint32_t FOLD_I = N_ICH / P_ICH;
    constexpr uint32_t FOLD_O = N_OCH / P_OCH;
    static_assert(N_ICH % P_ICH == 0, "N_ICH must be divisible by P_ICH");
    static_assert(N_OCH % P_OCH == 0, "N_OCH must be divisible by P_OCH");
    constexpr uint32_t N_IM = N_IH * N_IW;
    constexpr uint32_t N_OM = N_OH * N_OW;

    std::array<uint32_t, 2> ifm_shape = {N_IM, N_ICH};
    std::array<uint32_t, 2> ofm_shape = {N_OM, N_OCH};
    data_stream<BIT_ACTV> s_input("s_input");
    data_stream<BIT_ACTV> s_input_golden("s_input_golden");
    gen_ifm<BIT_ACTV>(s_input, ifm_shape);
    gen_ifm<BIT_ACTV>(s_input_golden, ifm_shape);

    ap_int<BIT_WGHT> weight[N_OCH][K*K][N_ICH];
    for(uint32_t ic = 0; ic < N_ICH; ++ic) {
        for(uint32_t oc = 0; oc < N_OCH; ++oc) {
            for(uint32_t k = 0; k < K*K; ++k) {
                ap_int<BIT_WGHT> val = ic*N_OCH*K*K + oc*K*K + k;
                weight[oc][k][ic] = val;
            }
        }
    }

    ap_uint<P_OCH * P_ICH * BIT_WGHT> weight_reshape[FOLD_O][FOLD_I][K*K];

    for (uint32_t fo = 0; fo < FOLD_O; ++fo) {
        for (uint32_t fi = 0; fi < FOLD_I; ++fi) {
            for (uint32_t k = 0; k < K*K; ++k) {
                ap_uint<P_OCH * P_ICH * BIT_WGHT> w = 0;
                for (uint32_t o = 0; o < P_OCH; ++o) {
                    for (uint32_t i = 0; i < P_ICH; ++i) {
                        uint32_t oc = fo * P_OCH + o;
                        uint32_t ic = fi * P_ICH + i;
                        ap_uint<BIT_WGHT> val = weight[oc][k][ic];
                        w(SLICE(BIT_WGHT, P_ICH * o + i)) = val;
                    }
                }
                weight_reshape[fo][fi][k] = w;
            }
        }
    }

    data_stream<BIT_ACTV*P_ICH> s_input_e("s_input_e");
    expand_width<BIT_ACTV, P_ICH * BIT_ACTV, N_IH * N_IW * N_ICH>(s_input, s_input_e);

    data_stream<BIT_CONV*P_OCH> s_output_e("s_output_e");
    deconv<P_ICH, P_OCH, N_ICH, N_OCH, N_IH, N_IW, K, P, S, O_P, BIT_ACTV, BIT_WGHT, BIT_CONV>(
        s_input_e, s_output_e, weight_reshape
    );

    data_stream<BIT_CONV> s_output("s_output");
    reduce_width<BIT_CONV * P_OCH, BIT_CONV, N_OH * N_OW * FOLD_O>(s_output_e, s_output);

    data_stream<BIT_CONV> s_output_golden("s_output_golden");
    deconv_golden<N_ICH, N_OCH, N_IH, N_IW, K, P, S, O_P, BIT_ACTV, BIT_WGHT, BIT_CONV>(
        s_input_golden, s_output_golden, weight
    );
    auto error_cnt = check_afm<BIT_CONV, N_OH, N_OW, N_OCH>(s_output_golden, s_output, true);
    if(error_cnt > 0) {
        std::cout << "Test Failed! " << error_cnt << " errors" << std::endl;
        return 1;
    } else {
        std::cout << "Test Passed! " << std::endl;
        return 0;
    }
}