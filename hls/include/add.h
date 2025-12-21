#pragma once
#ifndef ADD_H_
#define ADD_H_

#include "stream_tools.h"
#include "unet_v1_params.h"

void add(data_stream<I_BIT>& in1, data_stream<O_BIT>& in2, data_stream<O_BIT>& out)
{
    assert(out.empty());
    unsigned VEC_LEN = in1.size();
    ap_uint<I_BIT> input1;
    ap_int<O_BIT> input2;
    ap_uint<O_BIT> output;
    for (unsigned i = 0; i < VEC_LEN; ++i)
    {
        input1 = in1.read();
        input2 = in2.read();
        output = input1 + input2;
        out.write(output);
    }
}
#endif