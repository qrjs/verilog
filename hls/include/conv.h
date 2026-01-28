#pragma once
#ifndef __CONV_H__
#define __CONV_H__

#include "stream_tools.h"
#include "unet_v1_params.h"

// Golden reference for convolution
template <unsigned N_ICH,
          unsigned N_OCH,
          unsigned N_IH,
          unsigned N_IW,
          unsigned K,
          unsigned P,
          unsigned S,
          unsigned A_BIT,
          unsigned W_BIT,
          unsigned B_BIT>
void conv_golden(data_stream<A_BIT>& in,
                 data_stream<B_BIT>& out,
                 const ap_int<W_BIT> weight[N_OCH][K * K][N_ICH])
{
    constexpr unsigned N_OH = (N_IH + 2 * P - K) / S + 1;
    constexpr unsigned N_OW = (N_IW + 2 * P - K) / S + 1;
    ap_int<A_BIT> input_buf[N_IH][N_IW][N_ICH];
    ap_int<B_BIT> output_buf[N_OH][N_OW][N_OCH];

    for (unsigned ih = 0; ih < N_IH; ++ih)
    {
        for (unsigned iw = 0; iw < N_IW; ++iw)
        {
            for (unsigned ic = 0; ic < N_ICH; ++ic)
            {
                input_buf[ih][iw][ic] = in.read();
            }
        }
    }
    for (unsigned oh = 0; oh < N_OH; ++oh)
    {
        for (unsigned ow = 0; ow < N_OW; ++ow)
        {
            for (unsigned oc = 0; oc < N_OCH; ++oc)
            {
                ap_int<B_BIT> acc = 0;
                for (unsigned kh = 0; kh < K; ++kh)
                {
                    for (unsigned kw = 0; kw < K; ++kw)
                    {
                        int ih = oh * S + kh - P;
                        int iw = ow * S + kw - P;
                        if (ih < 0 || ih >= N_IH || iw < 0 || iw >= N_IW)
                        {
                            // Padding
                            acc += 0;
                        }
                        else
                        {
                            for (unsigned ic = 0; ic < N_ICH; ++ic)
                            {
                                ap_int<A_BIT> x = input_buf[ih][iw][ic];
                                ap_int<W_BIT> w = weight[oc][kh * K + kw][ic];
                                ap_int<B_BIT> temp;
                                temp = x * w;
                                acc += temp;
                            }
                        }
                    }
                }
                output_buf[oh][ow][oc] = acc;
                out.write(acc);
            }
        }
    }
    // assert(in.empty());
    // assert(out.size() == N_OH * N_OW * N_OCH);
}

template <unsigned P_ICH,
          unsigned P_OCH,
          unsigned N_ICH,
          unsigned N_OCH,
          unsigned K,
          unsigned A_BIT,
          unsigned W_BIT,
          unsigned B_BIT,
          unsigned VEC_LEN>
void conv(data_stream<P_ICH * A_BIT>& in,
          data_stream<P_OCH * B_BIT>& out,
          const ap_uint<P_OCH * P_ICH * W_BIT> weight[N_OCH / P_OCH][N_ICH / P_ICH][K * K])
{
    static_assert(N_ICH >= P_ICH, "conv");
    static_assert(N_OCH >= P_OCH, "conv");
    static_assert(N_ICH % P_ICH == 0, "conv");
    static_assert(N_OCH % P_OCH == 0, "conv");

    constexpr unsigned FOLD_I = N_ICH / P_ICH;
    constexpr unsigned FOLD_O = N_OCH / P_OCH;
    constexpr unsigned ITERS = VEC_LEN;

    assert(in.size() == VEC_LEN * FOLD_I * K * K);
    assert(out.empty());

#pragma HLS bind_storage variable = weight type = rom_1p impl = lutram
    ap_uint<P_ICH * A_BIT> line[FOLD_I][K * K];
    ap_int<B_BIT> acc[P_OCH];
#pragma HLS ARRAY_PARTITION variable = acc complete dim = 1

    for (unsigned o = 0; o < P_OCH; ++o)
    {
#pragma HLS UNROLL
        acc[o] = 0;
    }

    for (unsigned it = 0; it < ITERS; ++it)
    {
        for (unsigned fo = 0; fo < FOLD_O; ++fo)
        {
            for (unsigned fi = 0; fi < FOLD_I; ++fi)
            {
                for (unsigned k = 0; k < K * K; ++k)
                {
#pragma HLS PIPELINE II = 1
                    // load
                    ap_uint<P_ICH * A_BIT> in_buf;
                    if (fo == 0)
                    {
                        in_buf = in.read();
                        // line[fi][k] = in_buf;
                    }
                    else
                    {
                        in_buf = line[fi][k];
                    }
                    ap_uint<P_OCH * P_ICH * W_BIT> wt_buf = weight[fo][fi][k];

                    for (unsigned i = 0; i < P_ICH; ++i)
                    {
#pragma HLS UNROLL
                        ap_uint<A_BIT> x = in_buf(SLICE(A_BIT, i));
                        for (unsigned o = 0; o < P_OCH; ++o)
                        {
                            ap_int<W_BIT> w = wt_buf(SLICE(W_BIT, P_ICH * o + i));
                            acc[o] += x * w;
                        }
                    }

                    if (k == K * K - 1)
                    {
                        ap_uint<P_OCH * B_BIT> out_buf;
                        for (unsigned o = 0; o < P_OCH; ++o)
                        {
#pragma HLS UNROLL
                            out_buf(SLICE(B_BIT, o)) = acc[o];
                            acc[o] = 0;
                        }
                        out.write(out_buf);
                    }
                }
            }
        }
    }

    assert(in.empty());
    assert(out.size() == VEC_LEN * FOLD_O);
    return;
};

#endif
