# 基于 Minisys FPGA 开发板的 RV32I 处理器系统设计报告

## 摘要

本项目面向“基于 FPGA 开发板的处理器设计”实验 B，从零实现了一个可在 Minisys 开发板上运行的简化 RV32I 处理器系统。基础部分完成了支持算术逻辑、访存、条件分支和无条件跳转指令的单周期 CPU；进阶部分在基础 CPU 上扩展了内存映射 I/O、性能计数器和五级流水线 CPU，并实现了数据前推、load-use 暂停、BTFNT 静态分支预测和预测错误 flush 等冒险处理机制。为了回应“程序能否在板上直接修改”的演示要求，系统还进一步加入了可写指令存储器、开关/按键指令装载器和按键去抖逻辑。系统使用 Verilog 编写，在 Vivado 2018.3 中完成仿真、综合、实现和上板验证。

最终验证结果表明：单周期 CPU 能正确运行求和测试程序并在 LED 上显示结果 55；系统集成版本能够通过内存映射 I/O 控制 LED 输出 0x55；流水线 CPU 能通过 nop、forwarding、load-use stall、branch prediction 和 branch flush 等专项测试；可编辑上板版本能够通过 SW 开关和 S1/S4 按键逐 byte 装载机器码程序，并在运行后显示新程序结果。资源与时序分析显示，流水线版本在功能上验证通过，但面积和时序压力明显高于单周期版本，体现了性能、面积和时序之间的权衡。

## 1. 实验目标与任务分析

实验 B 的基础要求是设计并实现一个支持基本指令集的单周期或多周期 CPU，并在 Minisys FPGA 开发板上完成综合、布局布线和硬件验证。进阶要求是在基础 CPU 上集成内存与 I/O 接口，构建完整可运行系统，并对系统性能瓶颈提出优化方案；同时引入流水线机制，对时钟频率、CPI 与吞吐量进行量化评估。

本项目采用如下技术路线：

| 项目 | 设计选择 |
| --- | --- |
| 硬件描述语言 | Verilog |
| 开发工具 | Vivado 2018.3 |
| 开发板 | Minisys，FPGA 型号 `xc7a100tfgg484-1` |
| 基础 CPU | RV32I 子集单周期 CPU |
| 进阶系统 | 单周期 CPU + 内存映射 I/O + 性能计数器 |
| 流水线拓展 | 五级流水线 CPU，支持 forwarding、stall、flush |
| 可编辑装载拓展 | 开关/按键逐 byte 写入指令存储器，支持板上更换测试程序 |
| 上板输出 | LED 显示程序运行结果低 8 位 |

本项目没有实现 Cache，而是采用统一片上指令存储器和数据存储器。报告中将其作为当前存储层次规划，并在改进方向中说明后续可扩展为 BRAM 或 Cache。

## 2. RV32I 子集设计

为了优先保证处理器正确运行，本项目选择实现最小可运行 RV32I 指令子集。支持的指令如下：

| 指令 | 类型 | 功能 |
| --- | --- | --- |
| `add` | R 型 | 两个寄存器相加 |
| `sub` | R 型 | 两个寄存器相减 |
| `and` | R 型 | 按位与 |
| `or` | R 型 | 按位或 |
| `addi` | I 型 | 寄存器与立即数相加 |
| `lw` | I 型 | 从数据存储器读一个字 |
| `sw` | S 型 | 向数据存储器写一个字 |
| `beq` | B 型 | 两个寄存器相等时分支 |
| `jal` | J 型 | 无条件跳转，并写回返回地址 |

系统统一采用 32 位数据宽度、32 位指令宽度和 5 位寄存器地址。PC 默认每周期加 4；`x0` 恒为 0，写入无效；数据存储器按字访问，当前版本不处理非对齐访问。

## 3. 单周期 CPU 设计

单周期 CPU 的顶层模块为 `cpu_top.v`，主要由 PC、指令存储器、译码器、控制器、立即数生成器、寄存器堆、ALU、数据存储器和分支单元组成。每条指令在一个时钟周期内完成取指、译码、执行、访存和写回。

核心模块如下：

| 模块 | 文件 | 作用 |
| --- | --- | --- |
| PC | `pc.v` | 保存当前指令地址，根据控制信号更新下一条 PC |
| 指令存储器 | `imem.v` | 根据 PC 读取当前指令 |
| 译码器 | `decoder.v` | 提取 opcode、funct、寄存器地址等字段 |
| 控制器 | `control.v` | 生成寄存器写、访存、分支、跳转等控制信号 |
| ALU 控制 | `alu_control.v` | 根据指令类型生成 ALU 运算类型 |
| 寄存器堆 | `regfile.v` | 提供两个读端口和一个写端口，保证 `x0=0` |
| 立即数生成 | `imm_gen.v` | 生成 I/S/B/J 型立即数 |
| ALU | `alu.v` | 完成加、减、与、或等运算 |
| 数据存储器 | `dmem.v` | 支持 `lw` 与 `sw` |
| 分支单元 | `branch_unit.v` | 判断 `beq` 是否跳转 |

单周期 CPU 的 PC 选择逻辑包括 `PC+4`、branch target 和 jal target。对于普通顺序执行指令，下一条 PC 为 `PC+4`；对于 `beq`，当 ALU 比较结果为相等时选择分支目标地址；对于 `jal`，直接选择跳转目标地址，并将 `PC+4` 写回目标寄存器。

### 单周期测试程序

基础测试程序计算 1 到 10 的累加和，并将结果写入 `dmem[0]`：

```asm
addi x1, x0, 0
addi x2, x0, 1
addi x3, x0, 11

loop:
add  x1, x1, x2
addi x2, x2, 1
beq  x2, x3, done
jal  x0, loop

done:
sw   x1, 0(x0)
```

预期结果为：

```text
dmem[0] = 55 = 0x37 = 8'b00110111
```

仿真结果如下：

```text
PASS: single-cycle sum dmem[0]=55
```

图 1 为单周期 CPU 仿真 PASS 截图，显示 `tb_single_cycle` 成功运行并得到 `dmem[0]=55`。

> 插图位置：请插入上传的 `tb_single_cycle` PASS 截图。

## 4. 完整系统集成设计

为了满足进阶要求中“集成内存与 I/O 接口，构建完整可运行系统”的要求，本项目新增 `system_top.v`，在已验证的单周期 CPU 基础上接入 `io_bus.v` 和 `perf_counter.v`。

### 4.1 内存映射 I/O

系统采用内存映射 I/O 方式，将普通数据存储器、LED、开关和性能计数器统一映射到 CPU 的 load/store 地址空间中。地址映射如下：

| 地址范围或地址 | 功能 |
| --- | --- |
| `0x00000000` 到 `0x000003ff` | 数据存储器 |
| `0x10000000` | LED 输出寄存器 |
| `0x10000004` | 开关输入寄存器 |
| `0x10000010` | cycle counter |
| `0x10000014` | instret counter |
| `0x10000018` | stall counter |
| `0x1000001c` | flush counter |

测试程序 `io_led.mem` 将固定值写入 `0x10000000`，上板后 LED 显示 `01010101`，即 `0x55`，证明 CPU 可以通过访存指令控制外设。

仿真结果如下：

```text
PASS: memory-mapped LED I/O and counters worked, cycles=29 instret=29
```

图 2 为 `tb_io_system` 仿真 PASS 截图，显示内存映射 LED I/O 和计数器均工作正常。

> 插图位置：请插入上传的 `tb_io_system` PASS 截图。

### 4.2 性能计数器

性能计数器模块 `perf_counter.v` 统计以下信息：

| 计数器 | 含义 |
| --- | --- |
| `cycle_count` | 复位结束后的周期数 |
| `instret_count` | 已提交指令数 |
| `stall_count` | 流水线暂停次数 |
| `flush_count` | 流水线 flush 次数 |

单周期系统中 `inst_valid` 每周期有效；流水线系统中仅 WB 阶段有效提交时计入 `instret_count`。性能计数器既可以通过调试端口观察，也可以通过内存映射地址读取。

`tb_perf_counter` 仿真结果如下：

```text
PASS: perf_counter counters are correct
```

图 3 为性能计数器仿真 PASS 截图。

> 插图位置：请插入上传的 `tb_perf_counter` PASS 截图。

### 4.3 板上可编辑指令装载扩展

原始版本的 `imem.v` 主要通过内置 ROM 或 `$readmemh` 初始化程序。该方式适合仿真和固定程序上板演示，但程序内容在 bitstream 生成后已经固化，若要更换程序，需要重新生成并下载 bitstream。为了支持“在板子上直接修改指令”的演示，本项目进一步将 `imem` 扩展为带写端口的指令存储器，并新增 `instr_loader.v` 和 `editable_minisys_top.v`。

该扩展提供两种模式：

| 模式 | 功能 |
| --- | --- |
| 装载模式 | CPU 保持复位，开关和按键负责向 `imem` 写入机器码 |
| 运行模式 | 释放 CPU 复位，CPU 从 `PC=0` 开始执行刚写入的程序 |

装载模式下，`sw[7:0]` 提供当前 8 位数据。每条 32 位指令分 4 次写入：

```text
第 1 次 btn_write：写 inst[7:0]
第 2 次 btn_write：写 inst[15:8]
第 3 次 btn_write：写 inst[23:16]
第 4 次 btn_write：写 inst[31:24]，并将完整 32 位指令写入 imem
```

按键功能如下：

| 板上按键 | RTL 信号 | 功能 |
| --- | --- | --- |
| S1 | `btn_write` | 写入当前 `sw[7:0]` byte |
| S2 | `btn_next` | 手动跳到下一条指令地址，连续输入完整程序时通常不需要使用 |
| S3 | `btn_clear` | 回到装载模式并清空装载地址 |
| S4 | `btn_run` | 进入运行模式，CPU 从 `PC=0` 执行 |
| S6 | `rst_btn` | 顶层复位 |

真实机械按键在按下和松开时会产生抖动。如果只做简单边沿检测，一次 S1 可能被识别为多次写入，导致机器码 byte 顺序被打乱。因此最终版本在 `instr_loader.v` 中加入了按键同步和去抖逻辑：先用两级寄存器同步异步按键信号，再要求按键状态稳定达到 `DEBOUNCE_CYCLES` 后才更新按键状态，并只在稳定状态的上升沿产生一次 `write/run/clear/next` 脉冲。仿真时通过参数将 `DEBOUNCE_CYCLES` 设为较小值，上板时使用默认较大值以适应真实按键。

LED 在装载模式下交替显示当前开关数据和当前装载地址/byte 槽位；进入运行模式后，LED 优先显示 `dmem[0][7:0]`。如果程序尚未写入 `dmem[0]`，则显示带最高位标记的 PC 调试信息，便于判断 CPU 是否已经开始取指运行。

该功能通过 `tb_editable_loader.v` 进行仿真验证。testbench 不直接修改 `imem`，而是模拟板上操作，将求和程序的每条 32 位机器码拆成 4 个 byte，通过 `sw` 和 `btn_write` 逐步写入。随后触发 `btn_run`，CPU 执行刚装载的程序，最终 LED 输出 `0x37`。仿真结果如下：

```text
PASS: editable loader wrote instructions through switches/buttons and CPU produced led=0x37
```

这说明当前系统已经支持“先在板上写入指令，再运行 CPU”的工作方式。实际操作中，32 位机器码按小端序输入，例如 `00a00093` 应依次输入 `93 00 a0 00`。每输入一个 byte 后按一次 S1；每满 4 个 byte 后，装载器自动将完整 32 位指令写入 `imem` 并进入下一条指令地址，因此连续输入完整程序时不需要按 S2。

板上额外验证了多组可编辑程序。例如：

| 程序功能 | 小端输入 byte 序列 | 预期 LED |
| --- | --- | --- |
| `addi x1, x0, 10; sw x1, 0(x0); jal x0, 0` | `93 00 a0 00 23 20 10 00 6f 00 00 00` | `00001010` |
| `7 + 8` 后写入 `dmem[0]` | `93 00 70 00 13 01 80 00 b3 81 20 00 23 20 30 00 6f 00 00 00` | `00001111` |
| `8 - 5` 后写入 `dmem[0]` | `93 00 80 00 13 01 50 00 b3 81 20 40 23 20 30 00 6f 00 00 00` | `00000011` |

这些结果说明该拓展不只是执行固定的 `sum.mem`，还能够在不重新生成 bitstream 的情况下，通过板上开关和按键修改并运行新的机器码程序。

## 5. 五级流水线 CPU 设计

流水线 CPU 顶层模块为 `pipeline_cpu_top.v`。该模块在单周期数据通路基础上拆分为五个阶段：

```text
IF -> ID -> EX -> MEM -> WB
```

各阶段功能如下：

| 阶段 | 功能 |
| --- | --- |
| IF | 根据 PC 取指，计算 `PC+4` |
| ID | 指令译码，读取寄存器，生成立即数和控制信号 |
| EX | ALU 运算，分支判断，计算访存地址和跳转目标 |
| MEM | 访问数据存储器 |
| WB | 将 ALU、访存或 `PC+4` 结果写回寄存器堆 |

流水线寄存器包括：

| 流水线寄存器 | 文件 | 作用 |
| --- | --- | --- |
| IF/ID | `if_id_reg.v` | 保存取指结果和 PC 信息 |
| ID/EX | `id_ex_reg.v` | 保存译码结果、立即数、寄存器值和控制信号 |
| EX/MEM | `ex_mem_reg.v` | 保存执行结果、store 数据和 MEM/WB 控制信号 |
| MEM/WB | `mem_wb_reg.v` | 保存访存结果和写回控制信号 |

流水线版本中，控制信号随流水线寄存器逐级传递，写回统一在 WB 阶段完成。分支预测在 ID 阶段给出预测方向和预测目标地址，实际分支结果在 EX 阶段确定；若预测错误，则清空错误路径指令并修正 PC。

## 6. 冒险处理机制

流水线 CPU 实现了三类主要冒险处理机制。

本项目最终采用的流水线冒险完整解决方案如下：

| 冒险类型 | 处理机制 | 对应模块/信号 | 验证方式 |
| --- | --- | --- | --- |
| ALU 数据冒险 | EX/MEM 与 MEM/WB 到 EX 的数据前推 | `forwarding_unit.v`，`forward_a`，`forward_b` | `hazard.mem` |
| load-use 数据冒险 | 暂停一个周期并插入 bubble | `hazard_unit.v`，`pc_write`，`if_id_write`，`id_ex_flush` | `load_use.mem` |
| 控制冒险 | BTFNT 静态分支预测 | `id_pred_taken`，`id_pred_target`，`predict_taken_debug` | `branch_predict.mem` |
| 预测错误 | flush 错误路径并修正 PC | `ex_mispredict`，`correct_pc`，`flush_debug` | `branch.mem` |

### 6.1 数据前推

对于相邻算术指令产生的数据相关，系统使用 `forwarding_unit.v` 将后级结果前推到 EX 阶段输入端。支持两类前推路径：

```text
EX/MEM -> EX
MEM/WB -> EX
```

例如：

```asm
addi x1, x0, 5
addi x2, x0, 3
add  x3, x1, x2
sub  x4, x3, x2
sw   x4, 0(x0)
```

该程序中 `sub` 立即使用上一条 `add` 的结果，前推机制保证无需插入 nop 即可正确执行。预期结果为 `dmem[0]=5`。

### 6.2 load-use 暂停

对于 `lw` 后紧跟使用加载结果的情况，数据要到 MEM/WB 阶段才可用，仅靠前推不能完全解决。因此 `hazard_unit.v` 检测 load-use 冒险，并插入一个 bubble：

- PC 保持不变；
- IF/ID 保持不变；
- ID/EX 控制信号清零。

测试程序如下：

```asm
addi x1, x0, 100
sw   x1, 0(x0)
lw   x2, 0(x0)
add  x3, x2, x2
sw   x3, 4(x0)
```

预期结果为 `dmem[1]=200`。性能计数中 `load_use` 测试的 `stall=1`，说明暂停机制被触发。

### 6.3 BTFNT 静态分支预测与 flush

本项目加入了 BTFNT 静态分支预测，即 Backward Taken, Forward Not Taken：

```text
向后条件分支：预测跳转
向前条件分支：预测不跳转
jal：预测跳转
```

在 ID 阶段，控制器和立即数生成器可以判断当前指令是否为 branch 或 `jal`，同时根据分支立即数的符号位判断目标地址相对当前 PC 是向前还是向后。如果预测跳转，则下一条 PC 选择预测目标地址，并清空 IF/ID 中已经取到的顺序路径指令。预测信息会随 ID/EX 流水线寄存器进入 EX 阶段。

在 EX 阶段，ALU 和 branch unit 得到实际跳转结果。若实际结果与预测结果不一致，或者实际目标地址与预测目标地址不同，则触发预测错误 flush，并将 PC 修正为真实目标地址或 `PC+4`。

向前分支预测不跳转的测试程序如下：

```asm
addi x1, x0, 1
addi x2, x0, 1
beq  x1, x2, label
addi x3, x0, 99
label:
addi x3, x0, 7
sw   x3, 0(x0)
```

预期结果为 `dmem[0]=7`。该测试是向前 taken 分支，BTFNT 会预测不跳转，因此 EX 阶段发现预测错误后触发 flush。另有 `branch_predict.mem` 使用向后 taken 分支，testbench 检测到 `predict_taken_debug` 有效，证明预测器确实产生了预测跳转。

`branch_predict.mem` 的测试思想是先写入 `dmem[0]=1`，随后执行一个向后且恒成立的 `beq`。由于目标地址在当前 PC 之前，BTFNT 会预测 taken，因此流水线能够较少触发预测错误 flush。该测试的性能输出为：

```text
PERF branch_predict: cycle=79 instret=51 stall=0 flush=25
```

与 `branch` 测试相比，`branch_predict` 在相同周期数内提交了更多指令，CPI 更低，体现了静态分支预测对循环型程序的性能收益。

流水线总仿真结果如下：

```text
PERF pipeline_nop: cycle=79 instret=41 stall=0 flush=36
PERF hazard: cycle=79 instret=40 stall=0 flush=37
PERF load_use: cycle=79 instret=40 stall=1 flush=36
PERF branch: cycle=79 instret=39 stall=0 flush=37
PERF branch_predict: cycle=79 instret=51 stall=0 flush=25
PASS: pipeline nop, forwarding, load-use stall, branch prediction, and branch flush tests passed
```

图 4 为 `tb_pipeline` 仿真 PASS 截图，包含 nop、forwarding、load-use stall、branch prediction 和 branch flush 的完整验证结果。

> 插图位置：请插入上传的 `tb_pipeline` PASS 截图。

## 7. Minisys 上板验证

本项目提供四个可上板顶层：

| 顶层模块 | 功能 | 预期 LED |
| --- | --- | --- |
| `minisys_top` | 单周期 CPU，运行求和程序 | `00110111` |
| `system_minisys_top` | 单周期 CPU + I/O + 性能计数器 | `01010101` |
| `pipeline_minisys_top` | 流水线 CPU，运行求和程序 | `00110111` |
| `editable_minisys_top` | 开关/按键写入指令存储器后运行 | 由输入程序决定，例如 `00110111`、`00001010`、`00001111`、`00000011` |

其中 `00110111` 为十进制 55，对应求和程序结果；`01010101` 为十六进制 `0x55`，对应内存映射 LED I/O 测试值。`editable_minisys_top` 的 LED 输出取决于现场通过 SW 和 S1 写入的机器码程序，适合演示“不重新生成 bitstream，也能在板上更换并运行程序”。

上板验证步骤为：在 Vivado 中选择对应顶层，运行综合、实现、生成 bitstream，然后通过 Hardware Manager 下载到 Minisys 开发板。实际照片显示 LED 输出与预期一致，说明这些顶层均能在硬件上运行。

图 5 为 `minisys_top` 或 `pipeline_minisys_top` 上板结果，LED 显示 `00110111`。

> 插图位置：请插入上传的 LED 为 `00110111` 的上板照片。

图 6 为 `system_minisys_top` 上板结果，LED 显示 `01010101`。

> 插图位置：请插入上传的 LED 为 `01010101` 的上板照片。

图 7 为 `editable_minisys_top` 上板演示结果。演示时先按 S3 清空装载状态，再通过 SW0~SW7 设置当前 byte，每个 byte 按一次 S1 写入，输入完成后按 S4 运行。实际测试中，求和程序输出 `00110111`，`addi/sw/jal` 短程序输出 `00001010`，加法程序输出 `00001111`，减法程序输出 `00000011`。

> 插图位置：请插入 `editable_minisys_top` 上板照片或视频截图。

## 8. 调试问题与修正过程

在实现和验证过程中，项目并不是一次完成，而是经过了多轮仿真、上板和设计修正。下面记录几个与 CPU 功能、流水线控制和性能统计直接相关的典型问题。

### 8.1 内存映射 I/O 初始测试失败

在验证 `system_top` 的内存映射 I/O 时，曾出现如下失败：

```text
FAIL: io_led expected led=0x55, got 0x00
```

该现象说明 CPU 没有执行预期的 I/O 测试程序，或者没有把写 LED 的 `sw` 指令正确送到 `io_bus`。排查时重点检查了三部分：CPU 外部数据总线接口、`io_bus` 的地址译码，以及 `system_top` 中 CPU、I/O 总线和性能计数器之间的连接关系。

修正后，单周期 CPU 增加外部数据总线接口，在普通内部 `dmem` 模式之外支持外接 `io_bus`。`io_bus` 对 `0x10000000` 地址进行译码，并在写使能有效时更新 LED 输出寄存器。`system_top` 负责把 CPU 的访存地址、写数据、读写使能连接到 `io_bus`，同时把 `io_bus` 的读数据返回 CPU。

再次运行后，`tb_io_system` 输出：

```text
PASS: memory-mapped LED I/O and counters worked, cycles=29 instret=29
```

说明 CPU 已经能够通过访存指令访问 I/O 地址，并正确控制 LED 寄存器。

### 8.2 性能计数器测试预期不一致

在验证 `perf_counter.v` 时，最初 testbench 中对 `cycle_count` 的期望值与实际输出不一致。问题并不是计数器主体逻辑错误，而是 testbench 对复位释放后的有效时钟周期数计算多算了一个周期。

性能计数器的设计逻辑为：

```text
cycle_count 每个复位后的有效时钟周期加 1
instret_count 在 inst_valid 有效时加 1
stall_count 在 stall 有效时加 1
flush_count 在 flush 有效时加 1
```

重新检查波形和 testbench 激励后，将 `tb_perf_counter.v` 中的期望周期数从 5 修正为 4，使其与复位释放后的实际有效周期一致。修正后输出：

```text
PASS: perf_counter counters are correct
```

这说明性能计数器的计数边界和 testbench 预期已经一致。

### 8.3 流水线初始仿真结果错误

流水线版本初次运行 `tb_pipeline` 时，出现过如下失败：

```text
FAIL: pipeline_nop expected dmem[0]=2, got 0
```

该现象说明流水线程序没有把预期结果写入数据存储器。由于 `pipeline_nop` 是带 nop 的最基础流水线测试，它失败说明问题不只可能出现在复杂冒险处理，也可能出现在流水线寄存器控制信号传递、写回时序、store 数据路径或 PC 更新逻辑。

最终修正重点包括：

1. 检查并补齐 IF/ID、ID/EX、EX/MEM、MEM/WB 四级流水线寄存器中的控制信号传递。
2. 确认写回阶段才对寄存器堆进行写操作，避免前后级数据时序混乱。
3. 修正 store 数据路径，使 `sw` 使用 `forward_b_data`，保证 store 指令在数据相关情况下写入的是前推后的正确值。
4. 对 branch 和 `jal` 同时清空 IF/ID 与 ID/EX 中的错误路径指令，避免错误指令继续向后级提交。
5. 在流水线顶层加入 `stall_debug`、`flush_debug`、`inst_valid_debug` 和性能计数输出，便于 testbench 观察。

修正后，流水线综合测试输出：

```text
PASS: pipeline nop, forwarding, load-use stall, branch prediction, and branch flush tests passed
```

同时性能计数显示：

```text
PERF load_use: cycle=79 instret=40 stall=1 flush=36
PERF branch: cycle=79 instret=39 stall=0 flush=37
```

其中 `load_use` 的 `stall=1` 证明暂停机制触发，`branch` 的 flush 次数增加说明分支清空机制生效。
同时，`branch_predict` 测试中的 `instret=51` 高于其他分支相关测试，说明向后分支预测跳转后，流水线能减少错误路径指令带来的额外开销。

### 8.4 流水线验证覆盖不足

流水线初步跑通后，如果只运行一个测试程序，无法证明 forwarding、load-use stall、branch prediction 和 branch flush 都正确。因此后续对 `tb_pipeline.v` 进行了扩展，使其依次运行五类程序：

| 测试程序 | 验证目标 | 预期结果 |
| --- | --- | --- |
| `pipeline_nop.mem` | 基础五级流水线是否跑通 | `dmem[0]=2` |
| `hazard.mem` | EX/MEM 与 MEM/WB 到 EX 的前推 | `dmem[0]=5` |
| `load_use.mem` | load-use 暂停 | `dmem[1]=200` |
| `branch.mem` | 分支 flush | `dmem[0]=7` |
| `branch_predict.mem` | 向后条件分支预测跳转 | `dmem[0]=1` |

扩展后，testbench 不只判断最终内存结果，还打印 `cycle`、`instret`、`stall`、`flush`，用于量化冒险处理开销。最终输出：

```text
PERF pipeline_nop: cycle=79 instret=41 stall=0 flush=36
PERF hazard: cycle=79 instret=40 stall=0 flush=37
PERF load_use: cycle=79 instret=40 stall=1 flush=36
PERF branch: cycle=79 instret=39 stall=0 flush=37
PERF branch_predict: cycle=79 instret=51 stall=0 flush=25
PASS: pipeline nop, forwarding, load-use stall, branch prediction, and branch flush tests passed
```

其中 `load_use` 测试出现一次 stall，`branch` 测试 flush 次数增加，说明 testbench 能够覆盖并区分不同类型的冒险处理。
`branch_predict` 测试则用于证明预测器不仅存在，而且能在向后分支场景下产生预测跳转行为。

### 8.5 板上可编辑装载的按键抖动问题

在实现 `editable_minisys_top` 后，仿真中 `tb_editable_loader` 能够通过，但首次上板手动输入程序时，出现了“按 S1 时 LED 有反馈，但按 S4 运行后结果不符合预期”的现象。该问题不是 CPU 数据通路本身错误，而是由于真实机械按键存在抖动：一次按键可能在 FPGA 时钟域内产生多个短脉冲，使装载器把一次 S1 操作误认为多次 byte 写入，最终导致指令 byte 顺序错乱。

修正方法是在 `instr_loader.v` 中加入按键同步和去抖：

1. 先用两级寄存器将 S1~S4 从外部异步输入同步到 `clk` 时钟域。
2. 为每个按键维护稳定计数器，只有输入状态持续稳定达到 `DEBOUNCE_CYCLES` 后才更新按键状态。
3. 在去抖后的稳定状态上升沿产生单周期脉冲，驱动 `write`、`next`、`clear` 和 `run` 操作。
4. `editable_minisys_top` 上板时使用较大的默认去抖周期，`tb_editable_loader` 仿真时将该参数设为较小值以缩短仿真时间。

修正后重新运行仿真，输出仍为：

```text
PASS: editable loader wrote instructions through switches/buttons and CPU produced led=0x37
```

上板重新生成 bitstream 后，通过手动输入不同程序，LED 能显示 `00110111`、`00001010`、`00001111` 和 `00000011` 等不同结果，说明可编辑指令装载功能在真实硬件上稳定工作。

### 8.6 时序未完全收敛

实现后，`minisys_top` 和 `pipeline_minisys_top` 的 WNS 为负：

```text
minisys_top: WNS = -0.967 ns
pipeline_minisys_top: WNS = -1.121 ns
```

这说明在当前 100 MHz 时钟约束下仍存在时序违例。虽然上板 LED 功能验证正确，但从严格工程角度看，时序仍应进一步优化。可能原因包括组合逻辑路径较长、PC 更新路径和分支控制路径复杂、流水线冒险处理逻辑增加了关键路径压力。

后续可采用以下方式优化：

1. 降低约束时钟频率，使时序先稳定通过。
2. 优化分支判断和 PC 选择路径。
3. 将指令存储器和数据存储器映射为 BRAM。
4. 减少组合逻辑层级，必要时进一步拆分流水级。

## 9. 性能、面积与时序分析

### 9.1 资源与时序统计

Vivado 实现后的资源和时序结果如下：

| Top | LUT | FF | BRAM | WNS |
| --- | ---: | ---: | ---: | ---: |
| `minisys_top` | 365 | 136 | 0 | -0.967 ns |
| `system_minisys_top` | 127 | 88 | 0 | 1.938 ns |
| `pipeline_minisys_top` | 9517 | 8968 | 0 | -1.121 ns |

其中 LUT 表示查找表资源，FF 表示触发器资源，BRAM 表示 Block RAM 资源。当前三个版本的 BRAM 均为 0，说明指令存储器和数据存储器没有被 Vivado 映射到专用块 RAM，而是由 LUT/寄存器等逻辑资源实现。

WNS 表示 Worst Negative Slack。当 WNS 大于等于 0 时，说明当前时钟约束下时序通过；当 WNS 小于 0 时，说明存在时序违例。`system_minisys_top` 的 WNS 为 `1.938 ns`，满足当前时序约束；`minisys_top` 和 `pipeline_minisys_top` 的 WNS 分别为 `-0.967 ns` 和 `-1.121 ns`，说明在当前 100 MHz 约束下仍有时序优化空间。虽然上板功能验证正确，但报告中仍需说明时序未完全收敛。

### 9.2 CPI 与吞吐量

流水线专项测试的性能计数结果如下：

| Test | cycle | instret | stall | flush | CPI |
| --- | ---: | ---: | ---: | ---: | ---: |
| `pipeline_nop` | 79 | 41 | 0 | 36 | 1.927 |
| `hazard` | 79 | 40 | 0 | 37 | 1.975 |
| `load_use` | 79 | 40 | 1 | 36 | 1.975 |
| `branch` | 79 | 39 | 0 | 37 | 2.026 |
| `branch_predict` | 79 | 51 | 0 | 25 | 1.549 |

CPI 计算公式为：

```text
CPI = cycle_count / instret_count
```

以板级 100 MHz 时钟估算吞吐量：

```text
Throughput_board = 100 MHz / CPI
```

对应结果如下：

| Test | CPI | 100 MHz 下吞吐量 |
| --- | ---: | ---: |
| `pipeline_nop` | 1.927 | 51.89 MIPS |
| `hazard` | 1.975 | 50.63 MIPS |
| `load_use` | 1.975 | 50.63 MIPS |
| `branch` | 2.026 | 49.36 MIPS |
| `branch_predict` | 1.549 | 64.56 MIPS |

从数据可见，load-use 测试由于插入一次 stall，能够在性能计数中体现暂停开销；向前 taken 分支测试会产生预测错误 flush，因此 CPI 高于预测命中的 `branch_predict` 测试。`branch_predict` 使用向后 taken 分支，BTFNT 能预测跳转方向，因此在同样 79 个周期内提交了更多指令，CPI 更低。这说明性能计数器能够反映流水线冒险处理和分支预测对性能的影响。

### 9.3 PPA 权衡分析

从面积角度看，单周期版本结构最简单，资源占用较少；系统集成版本加入 I/O 总线和性能计数器后，仍保持较低资源占用；流水线版本由于增加了 IF/ID、ID/EX、EX/MEM、MEM/WB 流水线寄存器，以及 forwarding unit、hazard unit 和更多控制逻辑，LUT 和 FF 占用显著增加。

从性能角度看，流水线 CPU 将指令执行拆分为多个阶段，理论上可以提高指令吞吐率。但本项目的测试程序规模较小，并且包含 flush 和 stall，因此实际 CPI 会受到冒险处理开销影响。加入 BTFNT 静态分支预测后，向后分支循环场景下的 `branch_predict` 测试 CPI 降至 1.549，明显低于预测错误较多的 `branch` 测试。流水线版本在功能上已能正确处理数据冒险和控制冒险，但当前实现的时序压力较大，在 100 MHz 约束下 WNS 为负。

从功耗角度看，流水线寄存器和额外控制逻辑会带来更多触发器翻转和组合逻辑活动，因此功耗预计高于单周期版本。由于本实验主要关注功能和 PPA 趋势，功耗部分以 Vivado Power Report 作为后续补充方向。

综合来看，流水线设计提升了处理器结构的扩展性和吞吐潜力，但代价是面积增加、控制复杂度提升和时序收敛难度增大。

## 10. 总结与改进方向

本项目从零完成了基于 Minisys FPGA 开发板的简化 RV32I 处理器系统。基础部分实现了单周期 CPU，并通过仿真和上板验证；进阶部分完成了内存映射 I/O、性能计数器和五级流水线 CPU；进一步拓展部分实现了开关/按键写入指令存储器，使系统能够在不重新生成 bitstream 的情况下，在板上直接修改并运行新的机器码程序。流水线 CPU 能通过 nop、forwarding、load-use stall、branch prediction 和 branch flush 等测试，说明数据通路、控制通路和冒险处理机制均能正确工作。

当前设计仍有以下改进方向：

1. 将指令存储器和数据存储器改造为 BRAM，提高存储资源利用效率。
2. 进一步优化 PC 更新、分支判断和 hazard 处理路径，改善 WNS。
3. 扩展更多 RV32I 指令，如 `xor`、`slt`、`bne`、`lui`、`jalr` 等。
4. 增加 Cache 或分层存储结构，提高对进阶要求中存储层次设计的支撑。
5. 为可编辑指令装载模式增加更友好的输入显示，例如用数码管显示当前指令序号、byte 序号和输入值。
6. 增加更长的汇编测试程序，验证复杂控制流和访存场景下的稳定性。
7. 在 Vivado 中补充功耗报告，形成更完整的 PPA 分析。

总体而言，本项目已经完成基础 CPU、完整系统集成、流水线机制、板上可编辑指令装载和性能量化分析，能够支撑实验 B 的基础要求、进阶要求和拓展展示说明。
