#pragma once
#ifndef STREAM_TOOLS_H_
#define STREAM_TOOLS_H_

#undef AP_INT_MAX_W
#define AP_INT_MAX_W 2048

#include <cstdint>
#include <ap_int.h>
#include <hls_stream.h>
#include <ap_axi_sdata.h>
#ifndef __SYNTHESIS__
#include <cassert>
#else
#define assert(fuck_hls)
#endif

template <unsigned WIDTH>
using my_axiu = ap_axiu<WIDTH, 0, 0, 0>;

template <unsigned WIDTH>
using data_stream = hls::stream<ap_uint<WIDTH>>;

template <unsigned WIDTH>
using axiu_stream = hls::stream<my_axiu<WIDTH>>;

#define SLICE(BIT, i) ((BIT) - 1 + (BIT) * (i)), ((BIT) * (i))

template <unsigned IN_W, unsigned OUT_W, unsigned VEC_LEN>
void reduce_width(data_stream<IN_W>& in, data_stream<OUT_W>& out)
{
    constexpr unsigned FOLD = IN_W / OUT_W;
    static_assert(IN_W >= OUT_W, "reduce_width");
    static_assert(IN_W % OUT_W == 0, "reduce_width");

    // assert(in.size() == VEC_LEN);
    // assert(out.empty());

#pragma HLS DATAFLOW

    for (unsigned i = 0; i != VEC_LEN; ++i)
    {
#pragma HLS PIPELINE II = FOLD
        ap_uint<IN_W> in_buf = in.read();
        for (unsigned f = 0; f != FOLD; ++f)
        {
#pragma HLS UNROLL
            ap_uint<OUT_W> out_buf = in_buf(SLICE(OUT_W, f));
            out.write(out_buf);
        }
    }

    // assert(in.empty());
    // assert(out.size() == VEC_LEN * FOLD);
    return;
};

template <unsigned IN_W, unsigned OUT_W, unsigned VEC_LEN>
void expand_width(data_stream<IN_W>& in, data_stream<OUT_W>& out)
{
    constexpr unsigned FOLD = OUT_W / IN_W;
    constexpr unsigned ITER = VEC_LEN / FOLD;
    static_assert(OUT_W >= IN_W, "expand_width");
    static_assert(OUT_W % IN_W == 0, "expand_width");
    static_assert(VEC_LEN % FOLD == 0, "expand_width");

    // assert(in.size() == VEC_LEN);
    // assert(out.empty());

#pragma HLS DATAFLOW

    for (unsigned i = 0; i != ITER; ++i)
    {
#pragma HLS PIPELINE II = FOLD
        ap_uint<OUT_W> out_buf;
        for (unsigned f = 0; f != FOLD; ++f)
        {
#pragma HLS UNROLL
            ap_uint<IN_W> in_buf = in.read();
            out_buf(SLICE(IN_W, f)) = in_buf;
        }
        out.write(out_buf);
    }

    // assert(in.empty());
    // assert(out.size() == VEC_LEN / FOLD);
    return;
};

template <unsigned WIDTH, unsigned VEC_LEN>
void copy_stream(data_stream<WIDTH>& in, data_stream<WIDTH>& out0, data_stream<WIDTH>& out1)
{
#pragma HLS DATAFLOW
    for (unsigned i = 0; i < VEC_LEN; ++i)
    {
#pragma HLS PIPELINE II = 1
        ap_uint<WIDTH> buf = in.read();
        out0.write(buf);
        out1.write(buf);
    }
    return;
};

template <unsigned WIDTH, unsigned N_CH0, unsigned N_CH1, unsigned VEC_LEN>
void comb_stream(data_stream<WIDTH>& in0, data_stream<WIDTH>& in1, data_stream<WIDTH>& out)
{
#pragma HLS DATAFLOW

    for (unsigned i = 0; i < VEC_LEN; ++i)
    {
        for (unsigned j = 0; j < N_CH0 + N_CH1; ++j)
        {
#pragma HLS PIPELINE II = 1
            ap_uint<WIDTH> buf;
            if (j < N_CH0)
            {
                buf = in0.read();
            }
            else
            {
                buf = in1.read();
            }
            out.write(buf);
        }
    }
    return;
};

template <unsigned WIDTH, unsigned VEC_LEN>
void pointer2stream(ap_uint<WIDTH>* in, data_stream<WIDTH>& out)
{
#pragma HLS DATAFLOW

    for (unsigned i = 0; i < VEC_LEN; ++i)
    {
#pragma HLS PIPELINE II = 1
        out.write(in[i]);
    }
    return;
};

template <unsigned IN_BIT, unsigned OUT_BIT, unsigned VEC_LEN>
void stream2pointer_u(data_stream<IN_BIT>& in, ap_uint<OUT_BIT>* out)
{
#pragma HLS DATAFLOW
    for (unsigned i = 0; i < VEC_LEN; ++i)
    {
#pragma HLS PIPELINE II = 1
        ap_uint<IN_BIT> temp = in.read();
        out[i] = (ap_int<OUT_BIT>)temp;
    }
    return;
};

template <unsigned IN_BIT, unsigned OUT_BIT, unsigned VEC_LEN>
void stream2pointer_s(data_stream<IN_BIT>& in, ap_int<OUT_BIT>* out)
{
#pragma HLS DATAFLOW
    for (unsigned i = 0; i < VEC_LEN; ++i)
    {
#pragma HLS PIPELINE II = 1
        ap_int<IN_BIT> temp = in.read();
        out[i] = (ap_int<OUT_BIT>)temp;
    }
    return;
};

template <unsigned WIDTH, unsigned VEC_LEN>
void add_last(data_stream<WIDTH>& in, axiu_stream<WIDTH>& out)
{
#pragma HLS DATAFLOW

    for (unsigned i = 0; i < VEC_LEN; ++i)
    {
#pragma HLS PIPELINE II = 1
        my_axiu<WIDTH> buf;
        buf.data = in.read();
        buf.keep = -1;
        buf.strb = -1;
        buf.last = (i != VEC_LEN - 1) ? 0x0 : 0x1;
        out.write(buf);
    }
    return;
};

#endif
