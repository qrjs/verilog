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
            // 【Bug 修复说明】: 累加器(acc)必须在每个输出通道折叠 (fo) 开始前重置为0。
            // 之前的代码将清零写在了外面，导致计算后续 fo 时混入了前面的旧结果。
            for (unsigned o = 0; o < P_OCH; ++o)
            {
#pragma HLS UNROLL
                acc[o] = 0;
            }
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
                        // 【Bug 修复说明】: 恢复本应存入 line buffer 的输入数据。
                        // 如果不写回，后续计算同一个输入块的其他输出通道(fo)时将读取到乱码。
                        line[fi][k] = in_buf;
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

                    // 【Bug 修复说明】: 输出逻辑必须等待所有输入通道折叠 (fi) 全部累加完毕，
                    // 并且整个卷积核权重 (k) 都计算完后，才可以向外输出当前帧像素的计算结果。
                    // 原代码只有 k 的判断，导致中间算了一部分输入层就重复输出了。
                    if (k == K * K - 1 && fi == FOLD_I - 1)
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
