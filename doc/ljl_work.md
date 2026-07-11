# 乘除法扩展工作记录

> 记录时间：2026-07-11  
> 涉及版本：v2.1.0（两阶段提交 `c5af128` → `a07d1a9`）

---

## 一、目标

在已有 RV32I 五级流水线 CPU 基础上，扩展 RV32M 乘除法指令集（M-extension），共 8 条指令：

| 指令 | funct3 | 说明 | 周期 |
|------|--------|------|------|
| MUL | 000 | 有符号乘法，取低 32 位 | 1 |
| MULH | 001 | 有符号乘法，取高 32 位 | 1 |
| MULHSU | 010 | 有符号×无符号，取高 32 位 | 1 |
| MULHU | 011 | 无符号乘法，取高 32 位 | 1 |
| DIV | 100 | 有符号除法 | **多周期** |
| DIVU | 101 | 无符号除法 | **多周期** |
| REM | 110 | 有符号求余 | **多周期** |
| REMU | 111 | 无符号求余 | **多周期** |

---

## 二、实现思路

### 2.1 整体架构

```
IF ─→ ID ─→ EX ─→ MEM ─→ WB
            │
            ├─ alu.v (单周期)
            │   ├─ ADD/SUB/AND/OR/XOR/SLT/SLTU
            │   ├─ SLL/SRL/SRA (位移新增)
            │   ├─ MUL/MULH/MULHSU/MULHU (乘法，1周期)
            │   └─ DIV/DIVU/REM/REMU (fallback，仅单周期 CPU 使用)
            │
            └─ div_unit.v (多周期，流水线 CPU 使用)
                ├─ FSM: IDLE → CALC(×32) → DONE
                └─ 恢复余数法（restoring algorithm）
```

**设计决策**：
- **乘法走 alu.v**：乘法是单周期组合逻辑，可映射到 FPGA 的 DSP48 硬核
- **除法走 div_unit.v**：32 次迭代无法在 10ns 时钟内完成，使用多周期 FSM
- **ALU_DIV/ALU_DIVU/ALU_REM/ALU_REMU 共用编码 `4'b1110`**：流水线 CPU 通过 div_unit 的 funct3 区分具体操作

### 2.2 关键模块

#### 2.2.1 `alu_control.v` — 指令译码

```
alu_op = 00 → ADD（load/store/lui）
alu_op = 01 → SUB（branch 比较）
alu_op = 10 → R-type → funct7[0]=1 ? M-extension : base RV32I
alu_op = 11 → I-type → funct3 译码（不检查 funct7[5]）
```

M-extension 通过 `funct7[0] = 1` 区分于 base RV32I（`funct7 = 7'b0000001` vs `funct7 = 7'b0000000` 或 `7'b0100000`）。

#### 2.2.2 `alu.v` — 单周期运算

新增运算：
- `ALU_SLTU`、`ALU_SLL`、`ALU_SRL`、`ALU_SRA` — RV32I 原先缺失的 ALU 操作
- `ALU_MUL`、`ALU_MULH`、`ALU_MULHSU`、`ALU_MULHU` — 乘法
- `ALU_DIV`/`ALU_DIVU`/`ALU_REM`/`ALU_REMU` — 组合除法 fallback

64 位中间结果（`mul_signed`、`mul_signed_u`、`mul_unsigned`）用于提取 MULH/MULHSU/MULHU 的高 32 位。

#### 2.2.3 `div_unit.v` — 多周期除法

- **算法**：恢复余数法，32 次迭代
- **FSM**：IDLE → CALC(iter 0..31) → DONE_S
- **边界处理**：
  - 除数为 0 → 商 = -1，余数 = 被除数
  - 有符号溢出（-2³¹ ÷ -1）→ 商 = -2³¹，余数 = 0
  - 有符号数取绝对值后再运算，最后恢复符号

#### 2.2.4 流水线除法暂停机制

除法需要 32+ 个周期，除法指令必须在 EX 阶段停留：

```
div_start = ex_is_div && !div_active   // 组合逻辑，立即有效
div_stall = div_active && !ex_div_done // 除法进行中
div_active: reg, 下一拍才变化
```

| 信号 | 冻结对象 | 方式 |
|------|---------|------|
| `div_stall` → `~pc_write` | PC（IF 阶段） | hazard_unit |
| `div_stall` → `~if_id_write` | IF/ID 寄存器 | hazard_unit |
| `div_stall` → `~ex_en` | ID/EX 寄存器 | id_ex_reg.en |
| `div_stall` → `~ex_en` | EX/MEM 寄存器 | ex_mem_reg.en |

---

## 三、BUG 修复记录

### BUG #1（P0）：除法指令被后续指令覆盖

**提交**：`a07d1a9`  
**影响文件**：`id_ex_reg.v`、`ex_mem_reg.v`、`hazard_unit.v`、`pipeline_cpu_top.v`

**问题描述**：
v2.1.0 初版 `c5af128` 中，ID/EX 和 EX/MEM 寄存器没有 `en`（使能）端口。除法期间虽然冻结了 PC 和 IF/ID，但 ID/EX 每周期照常更新，导致 DIV 指令在 EX 中仅停留 1 个周期就被后续指令覆盖。

**根因分析**：
```verilog
// v2.1.0 初版 — id_ex_reg 无条件锁存
always @(posedge clk or posedge rst) begin
    if (rst || flush) begin ... end
    else begin                       // ← 每周期都更新！
        reg_write_out <= reg_write_in;
        ...
    end
end
```

div_stall 只冻结了 PC 和 IF/ID，但 ID/EX 照常更新 → DIV 在 EX 中只停留一拍就被覆盖 → 除法永远无法完成。

**修复方案**：
1. `id_ex_reg.v` 新增 `input wire en`，`en=0` 时保持所有输出
2. `ex_mem_reg.v` 新增 `input wire en`，`en=0` 时保持
3. `hazard_unit.v` 中 `id_ex_flush` 加入 `& ~ex_stall`：除法期间不能 flush ID/EX
4. `pipeline_cpu_top.v` 连线 `ex_en = ~div_stall`，连接到两个寄存器的 `.en()` 端口

### BUG #2（P1）：I-type ALU 指令译码错误

**提交**：`c5af128`  
**影响文件**：`control.v`

**问题描述**：
ALU 指令中，R-type（`OPCODE_RTYPE`）和 I-type（`OPCODE_ITYPE`）的 funct3 编码相同，但区别在于 R-type 的 funct7[5] 区分 ADD/SUB 和 SRL/SRA。旧代码中 I-type 也用 `alu_op=2'b00`（与 load/store 相同），导致 ANDI/ORI/XORI 等指令被错误当作 ADD 执行。

**修复**：
```verilog
// 修复前
`OPCODE_ITYPE: begin
    alu_op = 2'b00;    // 错误：与 load/store 共用 ADD 路径
end

// 修复后
`OPCODE_ITYPE: begin
    alu_op = 2'b11;    // I-type 专用：funct3 译码，不检查 funct7[5]
end
```

在 `alu_control.v` 中 `alu_op=2'b11` 时直接按 funct3 分发，避免了 `SLLI funct7[5]=0` 被误判为 SUB 的问题。

### BUG #3（P2，未修复）：Vivado 综合组合除法器时序违规

**状态**：已识别，尚未修改代码  
**影响文件**：`alu.v`

**问题描述**：
`alu.v` 中包含 `$signed(a) / $signed(b)` 等组合除法代码。Vivado 综合器无法进行跨模块死代码分析，会独立推断 32 位组合除法器（800-1500 LUT，~30-60ns），远超出 10ns 时钟约束。即使流水线 CPU 走 div_unit 不使用这段代码，综合出的硬件仍会拉低整体时序。

**建议修复**：
将组合除法分支替换为死值 `y = 32'b0`，使 Vivado 优化掉整个除法路径。

### BUG #4（P2，未修复）：div_start 一拍间隙

**状态**：已识别，尚未修改代码  
**影响文件**：`pipeline_cpu_top.v`

**问题描述**：
`div_start` 是组合逻辑（当前周期立即有效），`div_active` 是寄存器（下一拍才变化）。在除法指令进入 EX 的第一拍，`div_start=1` 但 `div_active=0`，此时 `div_stall=0`、`ex_en=1`，EX/MEM 可能捕获 ALU 的错误结果。

**建议修复**：
```verilog
// 修复前
assign div_stall = div_active && !ex_div_done;

// 修复后
assign div_stall = (div_active && !ex_div_done) || div_start;
```

---

## 四、修改文件总览

### 第一阶段 (`c5af128`)：v2.1.0 功能实现

| 文件 | 改动 |
|------|------|
| `src/basic_components/riscv_defs.vh` | 新增 M-extension ALU 宏定义 |
| `src/basic_components/alu.v` | 新增乘除 + 位移运算 |
| `src/basic_components/alu_control.v` | 新增 M-ext 解码 + I-type 路径 |
| `src/basic_components/control.v` | I-type `alu_op=2'b11` 修复 |
| `src/pipeline_cycle/pipeline_cpu_top.v` | 除法控制逻辑 + div_unit 例化 |
| `src/pipeline_cycle/hazard_unit.v` | 新增 `ex_stall` 输入 |
| `src/pipeline_cycle/branch_unit.v` | 扩展 BLT/BGE/BLTU/BGEU |
| `src/extension_components/div_unit.v` | **新建** 多周期除法单元 |
| `src/single_cycle/single_cycle_cpu_top.v` | 适配新 ALU |

### 第二阶段 (`a07d1a9`)：P0 流水线冻结修复

| 文件 | 改动 |
|------|------|
| `src/pipeline_cycle/id_ex_reg.v` | **+en 端口**，除法期间冻结 |
| `src/pipeline_cycle/ex_mem_reg.v` | **+en 端口**，除法期间冻结 |
| `src/pipeline_cycle/hazard_unit.v` | `id_ex_flush & ~ex_stall` |
| `src/pipeline_cycle/pipeline_cpu_top.v` | `ex_en` 连线 |
| `src/basic_components/imem.v` | PROGRAM_ID=7 测试程序 |
| `src/basic_components/decoder.v` | 指令格式注释 |
| `src/basic_components/regfile.v` | 注释 |
| `doc/advanced_usage.md` | 地址空间 + 性能计数器文档 |
| `.gitignore` | 私有文件排除 |
| `tb/tb_mul_div.v` | **新建** M-extension testbench |
| `program/mul_div_full.mem` | **新建** 27 项全覆盖测试 |

---

## 五、测试计划

### 已完成
- [x] `tb_mul_div.v` 仿真框架搭建（流水线 CPU + 单周期 CPU 对照）
- [x] `mul_div.mem`：15 条指令烟雾测试（MUL/DIV/REM + ANDI/SLLI/ORI）
- [x] `mul_div_full.mem`：27 项全覆盖测试（8 条 M 指令 + 边界条件）

### 待完成
- [ ] Vivado 仿真验证（行为级 + 时序）
- [ ] 上板手动录入测试（级别①→②→③递增验证）
- [ ] BUG #3 alu.v 组合除法器时序修复
- [ ] BUG #4 div_start 一拍间隙修复
- [ ] 上板完整测试（下载比特流验证全部指令）

---

## 六、待解决问题

| # | 问题 | 严重程度 | 状态 |
|---|------|---------|------|
| BUG #3 | alu.v 组合除法器导致 Vivado 时序违规 | **高** — 上板必须修 | 未修复 |
| BUG #4 | div_start→div_active 一拍间隙 | **中** — 可能错结果 | 未修复 |
| — | 上板 MUL 实测验证 | **高** — 核心功能 | 待测试 |
| — | 上板 DIV/REM 实测验证 | **高** — 核心功能 | 待测试 |

---

## 七、参考

- RISC-V Spec v2.2, Chapter 7: "M" Standard Extension for Integer Multiplication and Division
- `doc/advanced_usage.md` — 地址空间与性能计数器使用说明
- `doc/vivado_project_update_guide.md` — Vivado 工程更新指南（私有）
- `doc/v2.1.0_update_notes.md` — v2.1.0 完整技术说明（私有）
