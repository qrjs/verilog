#pragma once
#ifndef UNET_V1_PARAMS_H_
#define UNET_V1_PARAMS_H_
#include "stream_tools.h"

constexpr unsigned DEFAULT_DEPTH = 4;
constexpr unsigned MULT_BIT = 64;
constexpr unsigned I_BIT = 8;
constexpr unsigned O_BIT = 8;

constexpr unsigned CONV_W_BIT = 6;
constexpr unsigned CONV_A_BIT = 4;
constexpr unsigned CONV_B_BIT = 14;
constexpr unsigned CONV_M_BIT = 24;
constexpr unsigned CONV_KH = 3;
constexpr unsigned CONV_KW = 3;
constexpr unsigned CONV_PH = 1;
constexpr unsigned CONV_PW = 1;
constexpr unsigned CONV_SH = 1;
constexpr unsigned CONV_SW = 1;

constexpr unsigned CONVTRANS_W_BIT = 7;
constexpr unsigned CONVTRANS_A_BIT = 6;
constexpr unsigned CONVTRANS_B_BIT = 20;
constexpr unsigned CONVTRANS_M_BIT = 16;
constexpr unsigned CONVTRANS_KH = 3;
constexpr unsigned CONVTRANS_KW = 3;
constexpr unsigned CONVTRANS_PH = 1;
constexpr unsigned CONVTRANS_PW = 1;
constexpr unsigned CONVTRANS_SH = 2;
constexpr unsigned CONVTRANS_SW = 2;
constexpr unsigned CONVTRANS_OPH = 1;
constexpr unsigned CONVTRANS_OPW = 1;

constexpr unsigned CONV_PCH = 4;
constexpr unsigned CONVTRANS_PCH = 4;
constexpr unsigned FINAL_PCH = 1;

constexpr unsigned MAXPL_PCH = 4;

void copy0_block(data_stream<I_BIT>& in, data_stream<I_BIT>& out1, data_stream<I_BIT>& out2);

#endif