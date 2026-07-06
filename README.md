# Minisys 实验 B CPU 项目骨架

这是一个从零开始的 Verilog 处理器课程设计骨架，用于 Minisys FPGA 开发板上的实验 B。

## 目录结构

| 目录 | 内容 |
| --- | --- |
| `src/` | CPU RTL 源码模块 |
| `tb/` | 仿真测试平台 |
| `program/` | 十六进制机器码初始化文件 |
| `doc/` | 小组分工、集成流程和报告说明 |
| `vivado/` | Minisys 约束文件模板 |

## 当前实现目标

- `cpu_top.v`：单周期 RV32I 子集 CPU。
- `pipeline_cpu_top.v`：五级流水线 CPU 骨架，包含前推、load-use 暂停和分支 flush。
- `minisys_top.v`：面向开发板的顶层模块，把程序结果低 8 位输出到 LED。

## 支持的基础指令

当前基础子集：

```text
add, sub, and, or
addi
lw, sw
beq
jal
```

`alu_control.v` 中已经预留了 `xor` 和 `slt` 的 ALU 控制码，后续可以继续扩展。

## 建议仿真命令

如果电脑上安装了 Icarus Verilog，可以在项目根目录运行：

```powershell
iverilog -g2012 -I src -o work/single_cycle_tb.vvp tb/tb_single_cycle.v src/*.v
vvp work/single_cycle_tb.vvp

iverilog -g2012 -I src -o work/pipeline_tb.vvp tb/tb_pipeline.v src/*.v
vvp work/pipeline_tb.vvp
```

如果使用 Vivado：

1. 新建 RTL Project。
2. 添加 `src/` 中所有 Verilog 文件。
3. 仿真时添加 `tb/` 中对应 testbench。
4. 上板时设置 `minisys_top` 为顶层模块。
5. 用 Minisys 官方约束替换 `vivado/minisys_template.xdc` 中的占位引脚。
6. 依次运行综合、实现、生成 bitstream 并烧录开发板。

## 推荐开展顺序

1. 先跑通 `cpu_top.v` 对应的单周期求和程序，期望 `dmem[0] = 55`。
2. 再跑通 `pipeline_cpu_top.v` 的带冒险测试程序。
3. 最后整理 Vivado 的资源、频率和仿真波形，用于报告中的 PPA 分析。
