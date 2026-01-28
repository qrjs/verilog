# Verilog 练习项目

本项目是一个数字 IC 设计练习项目，包含了四个核心计算模块 (`Add`, `Maxpool`, `Conv`, `Deconv`) 的 HLS模型与 RTL 实现。

**你的任务**：当前目录中的 RTL 与 HLS 代码均包含预设的 **Bug**。你需要通过仿真、调试和代码分析，修复这些错误，使所有模块的仿真结果通过 (`TEST PASSED`)。

## 操作说明 (How to Run)

### 1. 环境准备
在开始仿真前，请确保已安装相关的 EDA 工具 (如 VCS/Verdi) 和 Python 环境。
在 `rtl` 目录下，系统会自动调用 `set_env.sh` 设置环境变量。

运行过程中若报错：`fatal error: ap_int.h: No such file or directory`。
请打开 `hls/CMakeLists.txt` 将`include directories`里的路径改成HLS库的路径。
我们的服务器vivado一般安装2025.1和2020.2版本，路径分别是:
*   2025.1： `/tools/Xilinx/2025.1/Vitis/include`
*   2020.2： `/tools/Xilinx/Vitis_HLS/2020.2/include`

### 2. 生成测试数据
进入数据生成目录，运行脚本生成 Golden Data。
```bash
cd rtl/data
python3 gen_add.py      # 生成加法器数据
python3 gen_maxpool.py  # 生成池化数据
python3 gen_conv.py     # 生成卷积数据
python3 gen_deconv.py   # 生成反卷积数据
```

### 3. 运行 RTL 仿真
进入对应模块的测试目录运行仿真。
**以 Maxpool 为例**:
```bash
cd rtl/test/maxpool_2x2
make sim        # 编译并运行仿真
```
*   如果测试通过，终端将显示 `*** TEST PASSED ***`。
*   如果测试失败，请查看 `sim.log` 或启动波形调试。

### 4. 查看波形 (Verdi)
如果仿真失败，可以使用 Verdi 查看波形进行调试（需要图形化窗口）：
```bash
make verdi
```

### 5. 运行 HLS 仿真 (C++)
`hls` 目录包含对应的 C++ 算法实现，用于验证算法逻辑。
```bash
cd hls
mkdir -p build && cd build
cmake ..
make
./tb_maxpool    # 运行 Maxpool 的 C++ 测试
```

---

## 调试任务列表 (Debugging Tasks)

请按照以下顺序或建议进行调试。每个模块都考察了特定的数字电路设计知识点。

### 1. 加法器 (Add Module)
*   **文件路径**: `rtl/design/add.sv`
*   **考察知识点**:
    *   **AXI-Stream 握手协议**: 理解 `valid` (数据有效) 和 `ready` (下游反压) 信号的正确交互逻辑。
    *   **有符号/无符号数运算**: Verilog 中 `signed` 与 `unsigned` 的定义会对运算结果产生什么影响？
*   **任务**: 修复握手信号死锁问题，并确保数据精度正确。

### 2. 最大池化 (Maxpool Module) - **核心任务**
*   **文件路径**: `rtl/design/maxpool_2x2.sv`
*   **考察知识点**: 理解池化的原理和目的，完善缓冲 (Line Buffer) 的读写控制、二维数据流的计数器设计。
*   **调试指南**: 请设计不同cntr_h和cntr_w下的时序，按照正确的逻辑对不同行/列计数器在对应的各个时钟周期内程序的行为进行分析和修正，并补全下表：

    |cycle|row=0，col=0|row=0，col=1|row=1，col=0|row=1，col=1|
    |---|---|---|---|---|
    |  0 | | | | |
    |  1 | | | | |
    |  …… | | | | |

### 3. 卷积 (Conv Module)
*   **文件路径**: `rtl/design/conv.sv`, `rtl/design/conv_mac.sv`
*   **考察知识点**:
    *   **死锁与握手**: 分析 AXI-Stream 握手信号 (`valid`/`ready`) 逻辑，排查导致流水线挂死的原因。
    *   **边界与顺序**: 检查多层循环计数器是否存在 Off-by-one 偏差，以及通道数据流顺序是否正常。
*   **任务**: 修复死锁问题，校准计数器边界，并恢复正确的数据通道顺序。

### 4. 反卷积 (Deconv Module)
*   **文件路径**: `rtl/design/deconv.sv`, `rtl/design/deconv_mac.sv`
*   **考察知识点**:
    *   **有符号数算术**: 深入理解 Verilog 中 `signed` 关键字对加法和乘法运算位宽扩展及符号位的影响。
    *   **时序与逻辑**: 检查 Line Buffer 读地址生成的准确性，以及 Valid 信号与数据流的同步关系。
*   **任务**: 修正有符号数运算错误，修复读写控制逻辑，确保输出无异常。
---