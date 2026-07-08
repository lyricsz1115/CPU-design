# 程序存储器初始化文件

这些文件是 `$readmemh` 可直接读取的十六进制 RISC-V 机器码程序。

| 文件 | 用途 | 期望结果 |
| --- | --- | --- |
| `sum.mem` | 单周期 CPU 完整冒烟测试 | `dmem[0] = 55` |
| `pipeline_nop.mem` | 插入 nop 的流水线结构测试 | `dmem[0] = 2` |
| `hazard.mem` | ALU 数据前推测试 | `dmem[0] = 5` |
| `load_use.mem` | load-use 暂停测试 | `dmem[1] = 200` |
| `branch.mem` | 分支 flush 测试 | `dmem[0] = 7` |
| `io_led.mem` | 内存映射 LED I/O 测试 | `led = 8'h55` |
| `perf_demo.mem` | 性能计数演示程序 | 用于记录周期数和提交指令数 |

说明：

- `00000013` 是 `addi x0, x0, 0`，在 RISC-V 中常用作 `nop`。
- 这些程序先用于仿真验证，后续也可以作为上板演示程序的基础。
