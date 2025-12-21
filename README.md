# Tutorial Project Guide

## 1. 项目简介 (Project Introduction)
本项目是一个 Verilog 学习教程，旨在通过实现和调试 `add` (加法器), `maxpool` (最大池化), `conv` (卷积), `deconv` (反卷积) 等核心模块，帮助读者掌握 Verilog 代码编写、仿真及调试流程。

## 2. 代码结构简介 (Code Structure)

### HLS 代码例程 (`hls/`)
本目录包含与 RTL 模块对应的 High-Level Synthesis (HLS) C++ 实现，作为例程用于参考。
*   **`include/`**: 包含 HLS 核心算法实现的头文件。
    *   `add.h`: 加法器 HLS 实现。
    *   `conv.h`: 卷积 HLS 实现。
    *   `deconv.h`: 反卷积 HLS 实现。
    *   `maxpool.h`: 最大池化 HLS 实现。
    *   `stream_tools.h`, `utils.h`: 数据流处理及辅助工具。
*   **`test/`**: 包含 C++ Testbench，用于验证 HLS 算法的正确性。
    *   `tb_deconv.cpp`: 反卷积模块的测试平台。

### RTL 设计代码 (`rtl/design/`)
包含核心逻辑的 Verilog/SystemVerilog 实现：
*   **`add.sv`**: 加法器模块。
*   **`conv.sv`**: 卷积运算模块。
*   **`deconv.sv`**: 反卷积运算模块。
*   **`maxpool_2x2.sv`**: 2x2 最大池化模块。
*   **辅助模块**: `conv_mac.sv` (乘累加单元), `delayline.sv` (延时线), `ram.sv`, `rom.sv` (存储模型)。

### 验证环境 (`rtl/test/`)
包含各模块的测试平台 (Testbench) 和 Makefile：
*   `add/`, `conv/`, `deconv/`, `maxpool_2x2/`: 对应模块的独立测试目录。
*   每个目录下包含 `ut_<module>.sv` (测试代码) 和 `Makefile` (仿真脚本)。

### 数据生成 (`rtl/data/`)
包含用于生成测试激励和参考数据的 Python 脚本：
*   `gen_add.py`, `gen_conv.py`, `gen_deconv.py`, `gen_maxpool.py`。

## 3. 操作流程 (Operation Flow)

要成功运行仿真平台，请遵循以下步骤：

### 第一步：环境设置
在 `rtl` 目录下，确保 `set_env.sh` 脚本存在。仿真脚本会自动调用它来设置 `PROJECT_PATH` 环境变量。

### 第二步：生成测试数据
进入数据生成目录，运行对应的 Python 脚本生成输入数据和预期输出数据。
以 `add` 模块为例：
```bash
cd rtl/data
python3 gen_add.py
```
这将生成 `.bin` 格式的数据文件，供 Testbench 读取。

### 第三步：运行仿真
进入对应模块的测试目录，使用 `make` 命令运行仿真。
以 `add` 模块为例：
```bash
cd rtl/test/add
make sim       # 编译并运行仿真
```

### 第四步：查看仿真结果
测试结果会在终端中显示出来。
或者查看生成的日志文件 `sim.log` 确认结果。

如果仿真成功生成了波形文件 (`.fsdb`)，可以使用 Verdi 查看：（需要远程桌面）
```bash
make verdi
```

## 4. 测试标准 (Testing Standards)

*   **自动比对**: Testbench 会自动读取 Python 生成的预期数据 (Golden Data) 与 RTL 模块的输出进行逐一比对。
*   **随机激励**: 输入数据的有效信号 (`valid`) 和反压信号 (`ready`) 会被随机驱动，以验证模块在非理想握手情况下的鲁棒性。
*   **结果判定**:
    *   仿真结束后，终端和日志会打印测试摘要。
    *   如果所有输出与预期一致，显示 `*** TEST PASSED ***`。
    *   如果有不匹配，显示 `*** TEST FAILED ***` 并列出错误数量。

## 5. HLS C++ 仿真流程 (HLS C++ Simulation Flow)

本教程提供了 HLS C++ 代码的测试平台作为例程进行参考，可以通过 CMake 进行编译和运行，验证算法逻辑的正确性。

### 第一步：创建构建目录
进入 `hls` 目录并创建一个构建目录`build`。
```bash
cd hls
mkdir -p build
cd build
```

### 第二步：编译测试程序
使用 CMake 生成 Makefile 并进行编译。
```bash
cmake ..
make
```
编译成功后，将在 `build` 目录下生成对应的可执行文件：`tb_add`, `tb_conv`, `tb_deconv`, `tb_maxpool`。

### 第三步：运行测试
直接运行生成的可执行文件即可进行测试。
例如，运行反卷积模块的测试：
```bash
./tb_deconv
```
如果测试通过，终端会输出 "Test Passed!" 以及相关的统计信息。
