# 四人小组分工与集成流程

## 成员 A：取指前端

负责文件：

- `pc.v`
- `imem.v`
- `imm_gen.v`
- `if_id_reg.v`

主要任务：

- 完成 PC 更新逻辑。
- 完成指令存储器读取。
- 完成 `addi`、`beq`、`jal` 等立即数生成。
- 完成 IF/ID 流水线寄存器。

交付物：

- 立即数生成测试。
- PC 跳转逻辑说明。
- 报告中的“总体架构、取指阶段、立即数生成”部分。

## 成员 B：译码与执行

负责文件：

- `decoder.v`
- `control.v`
- `alu_control.v`
- `alu.v`
- `id_ex_reg.v`
- `forwarding_unit.v`

主要任务：

- 完成指令字段译码。
- 完成主控制器和 ALU 控制器。
- 完成 ALU 的加、减、与、或等运算。
- 完成 ID/EX 流水线寄存器。
- 完成 EX/MEM 和 MEM/WB 到 EX 的数据前推。

交付物：

- ALU 测试。
- 控制信号说明。
- 前推路径说明。
- 报告中的“控制器、ALU、数据前推机制”部分。

## 成员 C：存储、写回与上板

负责文件：

- `regfile.v`
- `dmem.v`
- `ex_mem_reg.v`
- `mem_wb_reg.v`
- `minisys_top.v`
- `vivado/minisys_template.xdc`

主要任务：

- 完成寄存器堆。
- 完成数据存储器。
- 完成 EX/MEM 和 MEM/WB 流水线寄存器。
- 完成板级顶层封装。
- 将运行结果输出到 LED 或数码管。

交付物：

- `lw/sw` 测试。
- 上板约束说明。
- 上板照片或演示视频。
- 报告中的“寄存器堆、存储器、板级验证”部分。

## 成员 D：集成、冒险检测与报告

负责文件：

- `cpu_top.v`
- `pipeline_cpu_top.v`
- `hazard_unit.v`
- `tb/`
- `program/`

主要任务：

- 完成单周期 CPU 顶层集成。
- 完成流水线 CPU 顶层集成。
- 完成 load-use 冒险检测和暂停。
- 完成分支和 `jal` 的 flush。
- 编写总 testbench 和测试程序。
- 汇总 Vivado 的资源、频率、周期数和 CPI。

交付物：

- 完整程序仿真结果。
- 冒险处理波形。
- PPA 对比表。
- 最终报告和 PPT 整合。

## 集成规则

- 先冻结模块端口，再改模块内部逻辑。
- 每个成员提交模块前，必须至少通过自己的模块测试或顶层程序测试。
- 每天固定一次集成，由成员 D 负责顶层合并。
- 集成失败时，先回到上一个能跑通的版本，再逐个模块接入排查。
- 每个阶段保留一个稳定里程碑：
  - `v1_single_basic`
  - `v2_single_full`
  - `v3_pipeline_nop`
  - `v4_pipeline_hazard`
  - `v5_board_final`

## 最低验收标准

- 单周期 CPU 能运行求和程序，结果为 `dmem[0] = 55`。
- 流水线 CPU 能运行无 nop 的冒险测试程序。
- 至少能展示三类冒险处理：前推、暂停、flush。
- Minisys 板上能显示程序运行结果。
- 每个成员都有源码、测试材料和报告章节，贡献度可追踪。
