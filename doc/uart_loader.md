# UART 指令装载器

## 功能

该装载器通过 Minisys 板载 CP2102 串口接收 32 位 RISC-V 指令，写入
256 x 32-bit 指令存储器。CPU 在装载期间保持复位，只有完整程序接收
成功后才允许执行 `RUN`。

串口参数为 `115200 8N1`：

- FPGA RX: `Y19`
- FPGA TX: `V18`
- 系统时钟: `100 MHz`

## 协议

请求固定为 12 字节：

```text
AA 49 CMD SEQ ADDR_L ADDR_H D0 D1 D2 D3 FLAGS CRC8
```

响应固定为 8 字节：

```text
AA 41 STATUS SEQ ADDR_L ADDR_H DETAIL CRC8
```

CRC 使用 CRC-8/ATM，参数为 `poly=0x07`、`init=0x00`、非反射、
`xorout=0x00`，覆盖 CRC 字节之前的全部内容。32 位指令在线路上按
小端顺序传输。

| CMD | 名称 | 字段 |
| --- | --- | --- |
| `01` | BEGIN | `ADDR=1..256` 表示程序长度，DATA/FLAGS 为 0 |
| `02` | WRITE | `ADDR` 为绝对 word 地址，DATA 为指令，FLAGS 为 0 |
| `03` | RUN | ADDR/DATA/FLAGS 为 0 |
| `04` | STOP | ADDR/DATA/FLAGS 为 0 |
| `05` | STATUS | ADDR/DATA/FLAGS 为 0 |

| STATUS | 名称 |
| --- | --- |
| `00` | OK |
| `01` | CRC_ERROR |
| `02` | BAD_CMD |
| `03` | BAD_ADDR |
| `04` | BAD_STATE |
| `05` | BUSY |
| `06` | INCOMPLETE |
| `07` | BAD_LENGTH |
| `08` | BAD_FLAGS |
| `09` | SEQ_CONFLICT |

响应中的 `SEQ` 始终回显请求序号。`ADDR` 和 `DETAIL` 的语义如下：

| 响应场景 | ADDR | DETAIL |
| --- | --- | --- |
| BEGIN 成功 | 本次程序长度 | `00` |
| WRITE 成功 | 实际提交的绝对 word 地址 | `00` |
| RUN/STOP 成功 | 当前已接收的唯一 word 数量 | `00` |
| STATUS 成功 | 当前已接收的唯一 word 数量 | 见下方状态位定义 |
| INCOMPLETE | 首个缺失的绝对 word 地址 | `00` |
| 其他错误 | 回显请求 ADDR | `DETAIL[1:0]` 为当前装载器状态 |

STATUS 响应的 `DETAIL[1:0]` 为装载器状态：`0=IDLE`、`1=CLEARING`、
`2=READY`、`3=RUNNING`；bit 2 表示装载会话有效，bit 3 表示预期范围内
的指令已经全部收到，其余位为 0。

PC 采用 stop-and-wait：每次只发送一个未确认请求，超时、`CRC_ERROR`
或 `BUSY` 时使用完全相同的帧和序号重试。默认允许 3 次重传，即包含
首次发送在内最多尝试 4 次。完全相同的重复请求会重放缓存响应；相同
SEQ 但内容不同的请求返回 `SEQ_CONFLICT`。WRITE 使用绝对地址，因此
重复帧不会造成后续指令错位。新 PC 进程的首个 BEGIN 若恰好与 FPGA
缓存中的旧 SEQ 冲突，上位机会换用下一个 SEQ 再尝试一次。

`BEGIN` 会先将全部 256 个 word 写为 `00000013` NOP，再返回 ACK。
程序应以跳转自环等方式结束，现有示例使用 `0000006f`；否则 CPU 会继续
执行后续 NOP。

`.mem` 支持 `@地址` 定位。地址空洞会自动补为 `00000013` NOP，以满足
RUN 的连续完整性检查；重复定义同一 word 地址会被上位机拒绝。

## Vivado 工程

在仓库根目录执行：

```powershell
& 'F:\Vivado\Vivado\2018.3\bin\vivado.bat' `
  -mode batch -source '.\Vivado\register_uart_project.tcl'
```

脚本会：

- 注册 UART RTL 和三个测试平台；
- 将 `.sv` 文件类型设为 SystemVerilog；
- 设置综合顶层为 `uart_editable_pipeline_system_top`；
- 只启用 `xdc/uart_pipeline_system.xdc`，避免旧 XDC 重复创建时钟；
- 设置默认仿真顶层为 `tb_uart_pipeline_system`。

逐项仿真：

```powershell
$vivado = 'F:\Vivado\Vivado\2018.3\bin\vivado.bat'
& $vivado -mode batch -source '.\Vivado\run_uart_tb.tcl' -tclargs tb_uart_program_packet_rx
& $vivado -mode batch -source '.\Vivado\run_uart_tb.tcl' -tclargs tb_uart_program_loader
& $vivado -mode batch -source '.\Vivado\run_uart_tb.tcl' -tclargs tb_uart_pipeline_system
```

## Python 上位机

安装依赖：

```powershell
python -m pip install -r .\Python\requirements.txt
```

枚举串口：

```powershell
python .\Python\cpu_uart_loader.py --list-ports
```

交互模式：

```powershell
python .\Python\cpu_uart_loader.py --port COM5
```

常用交互命令：

```text
begin 3
00a00093
00102023
0000006f
status
run
stop
```

直接装载 `.mem` 并运行：

```powershell
python .\Python\cpu_uart_loader.py --port COM5 --file .\program\sum.mem --run
```

Python 单元测试：

```powershell
python -B -m unittest discover -s .\Python\tests -v
```
