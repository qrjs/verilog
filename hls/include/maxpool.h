#ifndef MAXPOOL_H_
#define MAXPOOL_H_

#include "stream_tools.h"

template <unsigned P_CH, unsigned BIT>
ap_uint<P_CH * BIT> max(const ap_uint<P_CH * BIT>& x, const ap_uint<P_CH * BIT>& y)
{
#pragma HLS INLINE
    ap_uint<P_CH * BIT> z;
    for (unsigned i = 0; i < P_CH; ++i)
    {
#pragma HLS UNROLL
        ap_uint<BIT> a = x(SLICE(BIT, i));
        ap_uint<BIT> b = y(SLICE(BIT, i));
        ap_uint<BIT> c = a > b ? a : b;
        z(SLICE(BIT, i)) = c;
    }
    return z;
};

template <unsigned P_CH,
          unsigned N_OCH,
          unsigned A_BIT,
          unsigned N_OH,
          unsigned N_OW,
          unsigned N_BATCH>
void maxpool_2x2(data_stream<P_CH * A_BIT>& in, data_stream<P_CH * A_BIT>& out)
{
    static_assert(N_OCH >= P_CH, "maxpool_2x2");
    static_assert(N_OCH % P_CH == 0, "maxpool_2x2");
    static_assert(N_OH % 2 == 0, "maxpool_2x2");
    static_assert(N_OW % 2 == 0, "maxpool_2x2");

    constexpr unsigned FOLD = N_OCH / P_CH;
    constexpr unsigned ITER = N_BATCH * N_OH * N_OW * FOLD;
    // assert(in.size() == ITER);
    // assert(out.empty());

#pragma HLS DATAFLOW

    ap_uint<P_CH * A_BIT> line[N_OW / 2][FOLD];

    for (unsigned r = 0; r < N_BATCH * N_OH; ++r)
    {
        for (unsigned c = 0; c < N_OW; ++c)
        {
            for (unsigned f = 0; f < FOLD; ++f)
            {
#pragma HLS PIPELINE II = 1
                const unsigned idx = c >> 1;
                ap_uint<P_CH * A_BIT> in_buf = in.read();
                ap_uint<P_CH * A_BIT> out_buf;

                // 【Bug 修复说明】: 状态机通过 r 和 c 的奇偶性判断 2x2 窗口内的位置。
                // r & 0x1 == 0 代表“偶数行”(0, 2, 4...)。
                // 之前代码错误地写成了 (r & 0x1) != 0，误把“奇数行”当成了“偶数行”，导致状态错乱。
                if ((r & 0x1) == 0)
                {
                    if ((c & 0x1) == 0)
                    {
                        // state 0x0: 偶数行，偶数列 -> 新的 2x2 窗口左上角，直接存入 line buffer
                        line[idx][f] = in_buf;
                    }
                    else
                    {
                        // state 0x1: 偶数行，奇数列 -> 右上角，与同行的左上角(已存在 line buffer) 比较去最大值，存回缓冲
                        out_buf = max<P_CH, A_BIT>(in_buf, line[idx][f]);
                        line[idx][f] = out_buf;
                    }
                }
                else
                {
                    if ((c & 0x1) == 0)
                    {
                        // state 0x2: 奇数行，偶数列 -> 左下角，与上一行提取出的行最大值比较，存回缓冲
                        out_buf = max<P_CH, A_BIT>(in_buf, line[idx][f]);
                        line[idx][f] = out_buf;
                    }
                    else
                    {
                        // state 0x3: 奇数行，奇数列 -> 窗口的最后一个元素(右下角)，进行最终比较后输出
                        out_buf = max<P_CH, A_BIT>(in_buf, line[idx][f]);
                        out.write(out_buf);
                    }
                }
                // const unsigned state = ((r & 0x1) << 1) | (c & 0x1);
                // switch (state)
                // {
                // case 0x0:
                //     line[idx][f] = in_buf;
                //     break;
                // case 0x1:
                //     out_buf = max<P_CH, A_BIT>(in_buf, line[idx][f]);
                //     line[idx][f] = out_buf;
                //     break;
                // case 0x2:
                //     out_buf = max<P_CH, A_BIT>(in_buf, line[idx][f]);
                //     line[idx][f] = out_buf;
                //     break;
                // case 0x3:
                //     out_buf = max<P_CH, A_BIT>(in_buf, line[idx][f]);
                //     out.write(out_buf);
                //     break;
                // default:
                //     // assert(false);
                //     break;
                // }
            }
        }
    }

    // assert(in.empty());
    // assert(out.size() == ITER / 4);
    return;
};

#endif
