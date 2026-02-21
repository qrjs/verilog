#pragma once
#ifndef CONV_H_
#define CONV_H_

#include "stream_tools.h"

template<
    unsigned N_ICH,
    unsigned N_OCH,
    unsigned N_IH,
    unsigned N_IW,
    unsigned K,
    unsigned P,
    unsigned S,
    unsigned O_P,
    unsigned BIT_ACTV,
    unsigned BIT_WGHT,
    unsigned BIT_CONV
>
void deconv_golden(
    data_stream<BIT_ACTV>& in,
    data_stream<BIT_CONV>& out,
    const ap_int<BIT_WGHT> weight[N_OCH][K*K][N_ICH]
)
{
    constexpr unsigned N_OH = (N_IH - 1) * S + K - 2 * P + O_P;
    constexpr unsigned N_OW = (N_IW - 1) * S + K - 2 * P + O_P;
    ap_int<BIT_ACTV> line_buf[N_IH][N_IW][N_ICH];
    ap_int<BIT_CONV> output_buf[N_OH][N_OW][N_OCH];

    for(unsigned ih = 0; ih < N_IH; ++ih) {
        for(unsigned iw = 0; iw < N_IW; ++iw) {
            for(unsigned fi = 0; fi < N_ICH; ++fi) {
                line_buf[ih][iw][fi] = in.read();
            }
        }
    }

    for(unsigned oh = 0; oh < N_OH; ++oh) {
        for(unsigned ow = 0; ow < N_OW; ++ow) {
            for(unsigned oc = 0; oc < N_OCH; ++oc) {
                ap_int<BIT_CONV> acc = 0;
                for(unsigned kh = 0; kh < K; ++kh) {
                    for(unsigned kw = 0; kw < K; ++kw) {
                        int h_temp = oh - kh + P;
                        int w_temp = ow - kw + P;
                        if(h_temp >= 0 && h_temp % S == 0 && w_temp >= 0 && w_temp % S == 0) {
                            int ih = h_temp / S;
                            int iw = w_temp / S;
                            if(ih >= 0 && ih < N_IH && iw >= 0 && iw < N_IW) {
                                for(unsigned fi = 0; fi < N_ICH; ++fi) {
                                    ap_int<BIT_ACTV> x = line_buf[ih][iw][fi];
                                    ap_int<BIT_WGHT> w = weight[oc][kh * K + kw][fi];
                                    acc += x * w;
                                }
                            }
                        }
                    }
                }
                out.write(acc);
            }
        }
    }

    assert(in.empty());
    assert(out.size() == N_OH * N_OW * N_OCH);
}

template <unsigned P_ICH,
          unsigned P_OCH,
          unsigned N_ICH,
          unsigned N_OCH,
          unsigned N_IH,
          unsigned N_IW,
          unsigned K,
          unsigned P,
          unsigned S,
          unsigned O_P,
          unsigned A_BIT,
          unsigned W_BIT,
          unsigned B_BIT>
void deconv(data_stream<P_ICH * A_BIT>& in,
               data_stream<P_OCH * B_BIT>& out,
               const ap_uint<P_OCH * P_ICH * W_BIT> weight[N_OCH / P_OCH][N_ICH / P_ICH][K * K])
{
    constexpr unsigned N_OH = (N_IH - 1) * S + K - 2 * P + O_P;
    constexpr unsigned N_OW = (N_IW - 1) * S + K - 2 * P + O_P;
    constexpr unsigned FOLD_I = N_ICH / P_ICH;
    constexpr unsigned FOLD_O = N_OCH / P_OCH;

    unsigned LB_H = S + 1;
    ap_uint<P_ICH * A_BIT> line_buf[LB_H][N_IW][FOLD_I];
    ap_int<B_BIT> acc[P_OCH];
    // ap_int<B_BIT> output_buf[N_OH][N_OW][N_OCH];

    for (unsigned ih = 0; ih < S; ++ih)
    {
        for (unsigned iw = 0; iw < N_IW; ++iw)
        {
            for (unsigned fi = 0; fi < FOLD_I; ++fi)
            {
                line_buf[ih][iw][fi] = in.read();
            }
        }
    }
    unsigned ih_to_read = S;
    for (unsigned oh = 0; oh < N_OH; ++oh)
    {
        for (unsigned ow = 0; ow < N_OW; ++ow)
        {
            for (unsigned fo = 0; fo < FOLD_O; ++fo)
            {
                for (unsigned poc = 0; poc < P_OCH; ++poc)
                {
                    acc[poc] = 0;
                }
                for (signed kh = K - 1; kh >= 0; kh--)
                {
                    for (signed kw = K - 1; kw >= 0; kw--)
                    {
                        // 【Bug 修复说明】: 计算原始高度坐标时漏加了 Padding 补偿 (P)。
                        // 宽度方向有 +P，但高度方向原本只有 h_temp = oh - kh，这会导致
                        // 输入特征索引越界或错位（通常表现为上方大片的错误或者算出一个很怪异的地址）。
                        int h_temp = oh - kh + P;
                        int w_temp = ow - kw + P;
                        for (unsigned fi = 0; fi < FOLD_I; ++fi)
                        {
                            ap_uint<P_OCH * P_ICH * W_BIT> wt_buf = weight[fo][fi][kh * K + kw];
                            if (oh % S == 0 && ow % S == 0 && kh == K - 1 && kw == K - 1 && fo == 0)
                            {
                                unsigned iw = ow / S;
                                if (ih_to_read < N_IH)
                                {
                                    line_buf[ih_to_read % LB_H][iw][fi] = in.read();
                                    if (iw == N_IW - 1 && fi == FOLD_I - 1)
                                    {
                                        ih_to_read++;
                                    }
                                }
                            }
                            if (h_temp >= 0 && h_temp % S == 0 && w_temp >= 0 && w_temp % S == 0)
                            {
                                int ih = h_temp / S;
                                int iw = w_temp / S;
                                if (ih >= 0 && ih < N_IH && iw >= 0 && iw < N_IW)
                                {
                                    for (unsigned pic = 0; pic < P_ICH; ++pic)
                                    {
                                        unsigned ic = fi * P_ICH + pic;
                                        ap_uint<P_ICH * A_BIT> in_buf = line_buf[ih % LB_H][iw][fi];
                                        ap_uint<A_BIT> x = in_buf(SLICE(A_BIT, pic));
                                        for (unsigned poc = 0; poc < P_OCH; ++poc)
                                        {
                                            unsigned oc = fo * P_OCH + poc;
                                            ap_int<W_BIT> w =
                                                wt_buf(SLICE(W_BIT, P_ICH * poc + pic));
                                            acc[poc] += x * w;
                                        }
                                    }
                                }
                            }
                            if (kh == 0 && kw == 0 && fi == FOLD_I - 1)
                            {
                                ap_uint<P_OCH * B_BIT> out_buf;
                                for (unsigned poc = 0; poc < P_OCH; ++poc)
                                {
                                    out_buf(SLICE(B_BIT, poc)) = acc[poc];
                                    acc[poc] = 0;
                                }
                                out.write(out_buf);
                            }
                        }
                    }
                }
            }
        }
    }
    // assert(in.empty());
    // assert(out.size() == N_OH * N_OW * FOLD_O);
}


#endif
