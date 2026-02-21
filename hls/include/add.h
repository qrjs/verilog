#pragma once
#ifndef ADD_H_
#define ADD_H_

#include "stream_tools.h"
#include "unet_v1_params.h"

void add(data_stream<I_BIT>& in1, data_stream<O_BIT>& in2, data_stream<O_BIT>& out)
{
    assert(out.empty());
    unsigned VEC_LEN = in1.size();
    
    // 【Bug 修复说明】: 之前 input1 和 output 错误地被声明为 ap_uint (无符号数)。
    // 由于 input2 是有符号数，这会导致 C++ 隐式类型转换发生错误，
    // 把有符号负数当成极大的无符号正数进行相加。统一修改为 ap_int (有符号数)。
    ap_int<I_BIT> input1;
    ap_int<O_BIT> input2;
    ap_int<O_BIT> output;
    
    for (unsigned i = 0; i < VEC_LEN; ++i)
    {
        input1 = in1.read();
        input2 = in2.read();
        output = input1 + input2;
        out.write(output);
    }
}
#endif