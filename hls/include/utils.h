#pragma once
#ifndef UTILS_H_
#define UTILS_H_

#include <array>
#include <vector>
#include <string>
#include <iostream>
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <cassert>
#include "stream_tools.h"

template <unsigned DWIDTH>
uint32_t load_ifm(data_stream<DWIDTH>& ifm, unsigned length, std::string path)
{
    std::ifstream test_file(path);
    if (!test_file)
    {
        std::cout << "错误: 无法找到文件 :" << path << std::endl;
        std::cout << std::endl;
        return 1;
    }
    test_file.close();
    int32_t* ifm_buffer;
    ifm_buffer = (int32_t*)malloc(length * sizeof(int32_t));
    FILE* fp = fopen(path.c_str(), "rb");
    fread(ifm_buffer, 1, length * sizeof(int32_t), fp);
    fclose(fp);

    for (size_t i = 0; i < length; i++)
    {
        ifm.write(ifm_buffer[i]);
    }
    free(ifm_buffer);
    std::cout << path << "输入成功" << std::endl;
    return 0;
}

template <unsigned DWIDTH, unsigned H, unsigned W, unsigned C>
uint32_t check_afm(data_stream<DWIDTH>& golden, data_stream<DWIDTH>& test, bool print = false)
{
    uint32_t* ofm_buffer;
    ofm_buffer = (uint32_t*)malloc(H * W * C * sizeof(uint32_t));

    uint32_t error_cnt = 0;

    for (size_t i = 0; i < H * W * C; i++)
    {
        ofm_buffer[i] = golden.read();
        // std::cout << std::setfill(' ') << std::setw(4) << (uint32_t)ofm_buffer[i] << " ";
    }
    for (size_t h = 0; h < H; h++)
    {
        for (size_t w = 0; w < W; w++)
        {
            for (size_t c = 0; c < C; c++)
            {
                size_t i = h * W * C + w * C + c;
                auto temp = test.read();
                // std::cout << std::setfill(' ') << std::setw(4) << (uint32_t)temp << " ";
                if (temp != ofm_buffer[i])
                {
                    std::cout << "Mismatch at [" << h << "][" << w << "][" << c << "]"
                              << " golden=" << static_cast<int32_t>(ofm_buffer[i])
                              << " test=" << static_cast<int32_t>(temp) << std::endl;
                    error_cnt++;
                }
                else
                {
                    if (print)
                    {
                        std::cout << "Match at [" << h << "][" << w << "][" << c << "]"
                                  << " value=" << static_cast<int32_t>(temp) << std::endl;
                    }
                }
            }
        }
    }
    std::cout << std::endl;
    // assert(golden.empty());
    // assert(test.empty());
    return error_cnt;
}

template <unsigned DWIDTH, unsigned N_OH, unsigned N_OW, unsigned N_CH, unsigned P_CH>
uint32_t check_fm(data_stream<P_CH * DWIDTH>& test, std::string path, bool print = false)
{
    static_assert(P_CH > 0, "P_CH must be > 0");
    static_assert(N_CH % P_CH == 0, "N_CH must be divisible by P_CH");
    uint32_t FOLD = N_CH / P_CH;
    data_stream<DWIDTH> golden("golden");
    if (load_ifm<DWIDTH>(golden, N_OH * N_OW * N_CH, path))
    {
        return 1;
    }

    uint32_t* ofm_buffer;
    ofm_buffer = (uint32_t*)malloc(N_OH * N_OW * N_CH * sizeof(uint32_t));

    uint32_t error_cnt = 0;
    for (size_t i = 0; i < N_OH * N_OW * N_CH; i++)
    {
        ofm_buffer[i] = golden.read();
        // std::cout << std::setfill(' ') << std::setw(4) << (uint32_t)ofm_buffer[i] << " ";
    }
    for (size_t h = 0; h < N_OH; h++)
    {
        for (size_t w = 0; w < N_OW; w++)
        {
            for (size_t f = 0; f < FOLD; f++)
            {
                auto temp = test.read();
                test.write(temp);
                for (size_t pch = 0; pch < P_CH; pch++)
                {
                    uint32_t test_data = temp(SLICE(DWIDTH, pch));
                    size_t c = f * P_CH + pch;
                    size_t i = h * N_OW * N_CH + w * N_CH + c;
                    // std::cout << std::setfill(' ') << std::setw(4) << (uint32_t)temp << " ";
                    if (test_data != ofm_buffer[i])
                    {
                        std::cout << "Mismatch at [" << h << "][" << w << "][" << c << "]"
                                  << " golden=" << static_cast<int32_t>(ofm_buffer[i])
                                  << " test=" << static_cast<int32_t>(test_data) << std::endl;
                        error_cnt++;
                    }
                    else
                    {
                        if (print && h < 4 && w < 4) // 只打印前4行4列
                        {
                            std::cout << "Match at [" << h << "][" << w << "][" << c << "]"
                                      << " value=" << static_cast<int32_t>(test_data) << std::endl;
                        }
                    }
                }
            }
        }
    }
    if (error_cnt > 0)
    {
        std::cout << "Test Failed! " << error_cnt << " errors" << std::endl;
    }
    else
    {
        std::cout << "Test Passed! " << std::endl;
    }
    // assert(golden.empty());
    // assert(test.empty());
    return error_cnt;
}

#endif
