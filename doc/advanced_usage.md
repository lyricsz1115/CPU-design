# 进阶要求代码使用说明

## 当前新增内容

本次进阶代码在不破坏原单周期上板版本的前提下，新增了三类能力：

- 内存映射 I/O：通过写地址 `0x10000000` 控制 LED。
- 性能计数：统计周期数、提交指令数、stall 次数和 flush 次数。
- 流水线验证接口：输出 `stall_debug`、`flush_debug` 和 `inst_valid_debug`。

## 关键文件

| 文件 | 作用 |
| --- | --- |
| `src/perf_counter.v` | 性能计数器 |
| `src/io_bus.v` | 内存映射 I/O 和数据存储器 |
| `src/system_top.v` | 单周期 CPU + I/O + 性能计数的系统顶层 |
| `src/system_minisys_top.v` | `system_top` 的 Minisys 上板封装 |
| `src/pipeline_minisys_top.v` | 流水线 CPU 的 Minisys 上板封装 |
| `program/io_led.mem` | 写 LED I/O 寄存器的测试程序 |
| `program/perf_demo.mem` | 性能计数演示程序 |
| `tb/tb_io_system.v` | I/O 系统仿真测试 |
| `tb/tb_perf_counter.v` | 性能计数器仿真测试 |
| `tb/tb_pipeline.v` | 流水线综合冒险测试 |

## 地址映射

| 地址 | 含义 |
| --- | --- |
| `0x00000000` 到 `0x000003ff` | 普通数据存储器 |
| `0x10000000` | LED 输出寄存器 |
| `0x10000004` | 开关输入寄存器，仿真中由 `sw[7:0]` 提供 |
| `0x10000010` | `cycle_count` |
| `0x10000014` | `instret_count` |
| `0x10000018` | `stall_count` |
| `0x1000001c` | `flush_count` |

### 地址空间架构

地址译码由 `io_bus.v` 完成，判断标准为 `addr[31:10]` 的值：

| 地址范围 | 条件 | 映射到 |
| --- | --- | --- |
| `0x00000000` ~ `0x000003FF` | `addr[31:10] == 22'b0` | 普通数据存储器 (DMEM)，256×32bit |
| `0x10000000` ~ `0x1000001c` | `addr[31:10] != 22'b0` | I/O 寄存器空间，按具体地址译码 |

```text
cpu_top 的访存请求 (lw/sw)  ──→  io_bus 地址译码
                                    │
                     addr[31:10]==0 ?  ──是──→ DMEM (data_mem_selected)
                         │
                        否
                         │
                         ▼
                    case (addr)
                      0x10000000 → LED 输出寄存器
                      0x10000004 → SW  输入寄存器
                      0x10000010 → cycle_count
                      0x10000014 → instret_count
                      0x10000018 → stall_count
                      0x1000001c → flush_count
                      default    → 0
```

### 性能计数器详细说明

性能计数器由 `perf_counter.v` 模块实现，在硬件层面持续统计四个指标。它们被映射到 I/O 地址空间，CPU 可以通过 `lw` 指令在程序中直接读取当前计数值，实现对自身性能的自省。

| 地址 | 寄存器 | 读出的含义 | 计数条件 |
| --- | --- | --- | --- |
| `0x10000010` | `cycle_count` | 从复位释放到现在经历的有效时钟周期数 | 每个时钟周期 +1（rst=0 时） |
| `0x10000014` | `instret_count` | 已提交（退休）的指令总数 | WB 阶段 `inst_valid` 有效时 +1 |
| `0x10000018` | `stall_count` | 流水线因 load-use 冒险暂停的次数 | `stall` 信号有效时 +1 |
| `0x1000001c` | `flush_count` | 流水线因预测错误/重定向清空的次数 | `flush` 信号有效时 +1 |

> **单周期 vs 流水线的区别**：
> - 单周期 CPU（`system_top`）中：`inst_valid` 每周期固定为 1，stall 和 flush 恒为 0。
> - 流水线 CPU（`pipeline_cpu_top`）中：`inst_valid` 仅在 WB 阶段指令有效提交时置 1，stall 来自 load-use 暂停，flush 来自 `ex_mispredict | id_predict_redirect`。

### 在程序中读取性能计数器

CPU 可以通过普通的 `lw` 指令读取这些寄存器，实现在测试程序中对自身性能的测量。

**示例：测量一段代码消耗的周期数**

```asm
# 在被测代码之前读取 cycle_count
lw x10, 0x10000010(x0)    # x10 = 起始周期数

# ... 被测代码段 ...

# 在被测代码之后读取 cycle_count
lw x11, 0x10000010(x0)    # x11 = 结束周期数
sub x12, x11, x10          # x12 = 被测代码消耗的周期数
```

**示例：读取所有性能计数器并存入 DMEM**

```asm
lw x10, 0x10000010(x0)     # cycle_count
lw x11, 0x10000014(x0)     # instret_count
lw x12, 0x10000018(x0)     # stall_count
lw x13, 0x1000001c(x0)     # flush_count
sw x10, 0(x0)              # 保存到 dmem[0]
sw x11, 4(x0)              # 保存到 dmem[1]
sw x12, 8(x0)              # 保存到 dmem[2]
sw x13, 12(x0)             # 保存到 dmem[3]
```

**计算 CPI（每指令周期数）**：

```text
CPI = cycle_count / instret_count
```

仿真中 `tb_pipeline` 的 PERF 输出行就是通过 `debug_*` 端口读取这些计数器得到的：

```text
PERF pipeline_nop: cycle=79 instret=41 stall=0 flush=36
PERF load_use:     cycle=79 instret=40 stall=1 flush=36
PERF branch:       cycle=79 instret=39 stall=0 flush=37
```

其中 `load_use` 的 `stall=1` 证明了暂停机制触发了一次，`branch` 的 `flush=37` 说明分支预测错误导致了 37 次流水线清空。

## Vivado 仿真建议

建议按下面顺序跑：

1. `tb_single_cycle`：确认基础单周期 CPU 仍然得到 `dmem[0] = 55`。
2. `tb_perf_counter`：确认性能计数器功能正确。
3. `tb_io_system`：确认 `io_led.mem` 能把 LED 写成 `8'h55`。
4. `tb_pipeline`：一次性验证流水线 nop、前推、load-use stall 和 branch flush。

## 上板建议

保底上板版本：

- 顶层：`minisys_top`
- 程序：内置 `sum.mem` 等价程序，不依赖综合读取 `.mem`
- 预期 LED：`00110111`

进阶 I/O 上板版本：

- 顶层：`system_minisys_top`
- 程序：内置 `io_led.mem` 等价程序，不依赖综合读取 `.mem`
- 预期 LED：`01010101`

流水线上板版本：

- 顶层：`pipeline_minisys_top`
- 程序：内置 `sum.mem` 等价程序，不依赖综合读取 `.mem`
- 预期 LED：`00110111`

## 报告可写结论

代码层面已经具备：

- CPU、数据存储器、I/O 的系统级集成。
- 可运行测试程序。
- 基础内存映射 I/O。
- 流水线冒险验证接口。
- 周期数、提交指令数、stall 和 flush 的计数能力。

Vivado 验证后，可以据此补充 Fmax、LUT、FF、BRAM、CPI 和吞吐量对比表。

## Vivado `.mem` 路径注意

Vivado xsim 会把加入工程的 `.mem` 文件导出到仿真工作目录下，因此 testbench 中使用的是：

```verilog
"io_led.mem"
"hazard.mem"
```

而不是：

```verilog
"program/io_led.mem"
"program/hazard.mem"
```

如果看到 `cannot be opened for reading`，说明 `.mem` 文件没有加入仿真源，或 Vivado 仍在使用复制到工程目录里的旧文件副本。

## 综合上板时的程序来源

仿真时 testbench 仍然通过 `$readmemh` 加载 `.mem` 文件。

上板顶层为了避免 Vivado 综合阶段找不到 `.mem` 文件，使用 `imem.v` 内置程序：

| `PROGRAM_ID` | 程序 |
| --- | --- |
| `0` | `sum.mem` 等价程序 |
| `1` | `io_led.mem` 等价程序 |
| `2` | `pipeline_nop.mem` 等价程序 |
| `3` | `hazard.mem` 等价程序 |
| `4` | `load_use.mem` 等价程序 |
| `5` | `branch.mem` 等价程序 |

因此上板时如果综合日志里再看到 `could not open $readmem data file`，说明当前 top 没有使用 `USE_INIT_FILE(0)`，需要检查顶层参数。
