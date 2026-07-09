# 进阶要求证据收集清单

## 1. 上板照片

请拍摄三张照片，文件名建议如下：

| 文件名 | Vivado Top | 预期 LED | 说明 |
| --- | --- | --- | --- |
| `board_minisys_top_00110111.jpg` | `minisys_top` | `00110111` | 单周期 CPU 运行求和程序，结果为 55 |
| `board_system_minisys_top_01010101.jpg` | `system_minisys_top` | `01010101` | 单周期 CPU + 内存映射 I/O，LED 输出 0x55 |
| `board_pipeline_minisys_top_00110111.jpg` | `pipeline_minisys_top` | `00110111` | 流水线 CPU 运行求和程序，结果为 55 |

拍照时建议同框包含：

- Minisys 板子。
- LED 亮灯状态。
- Vivado Hardware Manager 或电脑屏幕上的当前 top / bit 文件名。

## 2. Testbench PASS 截图

请分别运行并截图 Tcl Console 的 PASS 行：

| 截图文件名 | Simulation Top | PASS 关键字 |
| --- | --- | --- |
| `sim_tb_single_cycle_pass.png` | `tb_single_cycle` | `PASS: single-cycle sum dmem[0]=55` |
| `sim_tb_perf_counter_pass.png` | `tb_perf_counter` | `PASS: perf_counter counters are correct` |
| `sim_tb_io_system_pass.png` | `tb_io_system` | `PASS: memory-mapped LED I/O and counters worked` |
| `sim_tb_pipeline_pass.png` | `tb_pipeline` | `PASS: pipeline nop, forwarding, load-use stall, branch prediction, and branch flush tests passed` |
| `sim_tb_editable_loader_pass.png` | `tb_editable_loader` | `PASS: editable loader wrote instructions through switches/buttons and CPU produced led=0x37` |

`tb_pipeline` 已增强输出，会同时打印：

```text
PERF pipeline_nop: cycle=... instret=... stall=... flush=...
PERF hazard: cycle=... instret=... stall=... flush=...
PERF load_use: cycle=... instret=... stall=... flush=...
PERF branch: cycle=... instret=... stall=... flush=...
PERF branch_predict: cycle=... instret=... stall=... flush=...
```

## 3. Vivado Utilization / Timing 数据

当前已经提取到的实现后数据：

| Top | LUT | FF | BRAM | WNS |
| --- | ---: | ---: | ---: | ---: |
| `minisys_top` | 365 | 136 | 0 | -0.967 ns |
| `system_minisys_top` | 127 | 88 | 0 | 1.938 ns |
| `pipeline_minisys_top` | 9517 | 8968 | 0 | -1.121 ns |

数据来源：

- `D:/vivado_project/cpu_design_clean/cpu_design_clean.runs/impl_1/minisys_top_utilization_placed.rpt`
- `D:/vivado_project/cpu_design_clean/cpu_design_clean.runs/impl_1/minisys_top_timing_summary_routed.rpt`
- `D:/vivado_project/cpu_design_clean/cpu_design_clean.runs/impl_1/system_minisys_top_utilization_placed.rpt`
- `D:/vivado_project/cpu_design_clean/cpu_design_clean.runs/impl_1/system_minisys_top_timing_summary_routed.rpt`
- `D:/vivado_project/cpu_design/cpu_design.runs/impl_1/pipeline_minisys_top_utilization_placed.rpt`
- `D:/vivado_project/cpu_design/cpu_design.runs/impl_1/pipeline_minisys_top_timing_summary_routed.rpt`

说明：

- `BRAM = 0` 表示当前指令存储器和数据存储器没有映射到 Block RAM，而是由 LUT/寄存器等逻辑资源实现。
- `WNS >= 0` 表示当前时钟约束下时序通过。
- `WNS < 0` 表示当前时钟约束下存在时序违例；功能上板正确，但报告中需要说明时序仍有优化空间。

## 4. CPI 与吞吐量表

计算公式：

```text
CPI = cycle_count / instret_count
Throughput = Fmax / CPI
```

如果只使用当前 100 MHz 板级时钟，也可以写：

```text
Throughput_board = 100 MHz / CPI
```

流水线专项测试表：

| Test | cycle | instret | stall | flush | CPI |
| --- | ---: | ---: | ---: | ---: | ---: |
| `pipeline_nop` | 79 | 41 | 0 | 36 | 1.927 |
| `hazard` | 79 | 40 | 0 | 37 | 1.975 |
| `load_use` | 79 | 40 | 1 | 36 | 1.975 |
| `branch` | 79 | 39 | 0 | 37 | 2.026 |
| `branch_predict` | 79 | 51 | 0 | 25 | 1.549 |

数据来源：`tb_pipeline` 仿真输出。

```text
PERF pipeline_nop: cycle=79 instret=41 stall=0 flush=36
PERF hazard: cycle=79 instret=40 stall=0 flush=37
PERF load_use: cycle=79 instret=40 stall=1 flush=36
PERF branch: cycle=79 instret=39 stall=0 flush=37
PERF branch_predict: cycle=79 instret=51 stall=0 flush=25
```

## 5. PPA 分析写法提示

可以在报告中写：

- 单周期版本结构简单，面积较小，但关键路径较长，吞吐率有限。
- 系统集成版本增加 `io_bus` 和 `perf_counter`，实现了完整 I/O 和性能观测能力。
- 流水线版本通过 IF/ID/EX/MEM/WB 五级结构提高吞吐率，并通过 forwarding、stall、flush 处理冒险。
- 当前 `pipeline_minisys_top` 在 100 MHz 约束下 WNS 为 `-1.121 ns`，说明仍存在时序瓶颈；关键路径可能与控制逻辑、冒险处理、PC 更新或存储访问路径有关。
- 后续优化方向包括降低时钟频率、优化分支/PC 路径、将存储器映射为 BRAM、减少组合逻辑层级，或进一步拆分流水级。
