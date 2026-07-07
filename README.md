# CPU-design

这是一个面向 `Minisys` FPGA 实验板的 Verilog CPU 课程设计工程。

当前已经确认：

- 单周期 CPU `cpu_top` 仿真通过
- 单周期 CPU 已在 `Minisys` 板上跑通
- 板级红色 LED 显示 `00110111`
- `00110111 = 0x37 = 55`，对应 `dmem[0] = 55`

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
- `pipeline_cpu_top.v`：五级流水 CPU 框架
- `minisys_top.v`：`Minisys` 板级顶层

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

## 建议的下一步

单周期版本稳定后，下一阶段建议先做流水线仿真，再考虑流水线上板：

1. 运行 `tb_pipeline.v`
2. 验证 `hazard.mem`
3. 验证 `load_use.mem`
4. 验证 `branch.mem`
5. 仿真稳定后再切换到流水线板级测试

## 交接说明

详细交接信息见：

- [doc/handoff_status.md](doc/handoff_status.md)

其中记录了：

- 当前稳定状态
- 已确认的板级引脚
- `sum.mem` 的 Vivado 路径注意事项
- Git 提交流程说明
