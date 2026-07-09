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
