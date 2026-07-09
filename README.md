# CPU-design

这是一个面向 `Minisys` FPGA 实验板的 Verilog CPU 课程设计工程。

当前已经确认：

- 单周期 CPU `cpu_top` 仿真通过
- 单周期 CPU 已在 `Minisys` 板上跑通
- 板级红色 LED 显示 `00110111`
- `00110111 = 0x37 = 55`，对应 `dmem[0] = 55`
- 进阶 I/O、性能计数、五级流水线和板上可编辑指令装载均已完成仿真验证
- `editable_minisys_top` 支持通过 SW 开关和 S1/S4 按键在板上写入并运行新程序，已加入按键去抖

## 目录结构

| 路径 | 说明 |
| --- | --- |
| `src/` | CPU RTL 源码 |
| `tb/` | 仿真测试文件 |
| `program/` | 程序初始化文件（`.mem`） |
| `vivado/` | 开发板约束文件 |
| `doc/` | 交接文档、报告相关说明 |

## 当前模块情况

- `cpu_top.v`：单周期 RV32I 子集 CPU
- `pipeline_cpu_top.v`：五级流水 CPU，支持 forwarding、load-use stall、BTFNT 静态分支预测和 flush
- `minisys_top.v`：`Minisys` 板级顶层
- `editable_minisys_top.v`：可通过开关/按键装载指令的板级顶层
- `instr_loader.v`：将 4 次 8-bit 开关输入组装成 1 条 32-bit 指令并写入 `imem`，包含按键同步和去抖

## 当前支持的指令

```text
add, sub, and, or
addi
lw, sw
beq
jal
```

## 已确认可用的板级映射

当前 [vivado/minisys_template.xdc](vivado/minisys_template.xdc) 已按本组使用的 `Minisys` 实验板更新：

- `clk` -> `Y18`，100MHz
- `rst_btn` -> `P20`，对应按键 `S6`，高电平复位
- `led[7:0]` -> 红色 LED `RLD0~RLD7`

板级输出逻辑为：

```text
led = debug_dmem0[7:0]
```

因此基础程序运行结束后，红色 LED 预期显示：

```text
00110111
```

## Vivado 使用中的关键注意事项

指令存储器 `imem` 通过 `$readmemh` 加载程序。

当前工程统一使用：

```verilog
.INIT_FILE("sum.mem")
```

这意味着：

- `program/sum.mem` 必须加入 Vivado 工程
- 否则仿真或综合时可能找不到程序文件

如果 Vivado 提示无法打开 `sum.mem`，按下面顺序检查：

1. 确认 `program/sum.mem` 已加入工程
2. 重新运行仿真或综合
3. 检查日志中是否还有 `$readmemh` 相关警告

如果综合阶段没有正确加载 `sum.mem`，常见现象是：

- bitstream 可以正常生成和下载
- 但板上所有 LED 全灭
- 原因是 `imem` 为空，CPU 实际没有执行程序

## 基础验证流程

### 1. 仿真验证

使用：

- [tb/tb_single_cycle.v](tb/tb_single_cycle.v)

预期输出：

```text
PASS: single-cycle sum dmem[0]=55
```

### 2. 板级验证

1. 以 `minisys_top` 作为顶层生成 bitstream
2. 使用 Vivado Hardware Manager 下载到板子
3. 如有需要，按一下 `S6` 再松开
4. 观察红色 LED

预期结果：

```text
00110111
```

## 当前建议验证流程

1. 运行 `tb_single_cycle.v`，确认单周期求和程序输出 `55`。
2. 运行 `tb_io_system.v`，确认内存映射 LED I/O 输出 `0x55`。
3. 运行 `tb_perf_counter.v`，确认 cycle、instret、stall、flush 计数正确。
4. 运行 `tb_pipeline.v`，确认 nop、forwarding、load-use stall、BTFNT 分支预测和 flush 全部通过。
5. 运行 `tb_editable_loader.v`，确认开关/按键逐 byte 装载程序后 CPU 输出 `0x37`。
6. 上板时分别选择 `minisys_top`、`system_minisys_top`、`pipeline_minisys_top` 或 `editable_minisys_top` 作为顶层生成 bitstream。

## 交接说明

详细交接信息见：

- [doc/handoff_status.md](doc/handoff_status.md)
- [doc/advanced_usage.md](doc/advanced_usage.md)

其中记录了：

- 当前稳定状态
- 已确认的板级引脚
- `sum.mem` 的 Vivado 路径注意事项
- Git 提交流程说明

## 进阶代码入口

进阶要求相关入口：

- `system_top`：单周期 CPU + 内存映射 I/O + 性能计数。
- `system_minisys_top`：进阶 I/O 上板顶层。
- `pipeline_minisys_top`：流水线 CPU 上板顶层。
- `editable_minisys_top`：开关/按键写入指令存储器的可编辑上板顶层，真实按键输入已加入去抖。
- `tb_io_system`：I/O 系统仿真。
- `tb_perf_counter`：性能计数仿真。
- `tb_pipeline`：流水线冒险综合测试，覆盖数据前推、load-use 暂停、BTFNT 分支预测和 flush。
- `tb_editable_loader`：模拟开关/按键逐 byte 写入指令，再运行 CPU。

## 可编辑指令装载模式

`editable_minisys_top` 支持在板子上通过开关和按键写入指令存储器：

```text
装载模式：CPU 保持复位，开关/按键写 imem
运行模式：CPU 从 PC=0 开始执行刚写入的程序
```

输入方式：

```text
sw[7:0]      当前 8-bit 指令片段
btn_write/S1 写入当前 byte，4 次组成 1 条 32-bit 指令
btn_next/S2  跳到下一条指令地址，连续输入完整程序时通常不用按
btn_clear/S3 回到装载模式并清零装载地址
btn_run/S4   开始运行 CPU
rst_btn/S6   顶层复位
```

写入顺序为小端序：

```text
第 1 次写 inst[7:0]
第 2 次写 inst[15:8]
第 3 次写 inst[23:16]
第 4 次写 inst[31:24]，随后整条指令写入 imem
```

仿真验证：

```text
PASS: editable loader wrote instructions through switches/buttons and CPU produced led=0x37
```

上板操作要点：

1. 按 S3 清空装载状态。
2. 按板子丝印编号设置 `SW0` 到 `SW7`。
3. 每输入一个 byte，按一次 S1。
4. 每满 4 个 byte，装载器会自动写入一条 32-bit 指令并进入下一条地址。
5. 连续输入完整程序时不需要按 S2。
6. 输入完成后按 S4 运行。
7. LED 显示 `dmem[0][7:0]`；如果 `dmem[0]` 还没有被写入，则显示 PC 调试信息。

已经手动验证过的短程序：

| 功能 | 小端输入 byte 序列 | 预期 LED |
| --- | --- | --- |
| 输出 10 | `93 00 a0 00 23 20 10 00 6f 00 00 00` | `00001010` |
| 7 + 8 输出 15 | `93 00 70 00 13 01 80 00 b3 81 20 00 23 20 30 00 6f 00 00 00` | `00001111` |
| 8 - 5 输出 3 | `93 00 80 00 13 01 50 00 b3 81 20 40 23 20 30 00 6f 00 00 00` | `00000011` |

`vivado/editable_minisys_template.xdc` 已按 Minisys 硬件手册映射：

```text
sw[7:0] = SW7~SW0
btn_write = S1
btn_next  = S2
btn_clear = S3
btn_run   = S4
rst_btn   = S6
```
