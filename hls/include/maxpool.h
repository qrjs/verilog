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
                if ((r & 0x1) != 0)
                {
                    if ((c & 0x1) == 0)
                    {
                        // 0x0
                        line[idx][f] = in_buf;
                    }
                    else
                    {
                        // 0x1
                        // out_buf = max<P_CH, A_BIT>(in_buf, line[idx][f]);
                        line[idx][f] = in_buf;
                    }
                }
                else
                {
                    if ((c & 0x1) == 0)
                    {
                        // 0x2
                        out_buf = max<P_CH, A_BIT>(in_buf, line[idx][f]);
                        line[idx][f] = out_buf;
                    }
                    else
                    {
                        // 0x3
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
