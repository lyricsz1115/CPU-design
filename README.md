# CPU-design

Verilog CPU course project for the `Minisys` FPGA board.

Current verified status:

- Single-cycle CPU (`cpu_top`) passes simulation.
- Single-cycle CPU is verified on `Minisys`.
- Board output shows `00110111`, which matches `dmem[0] = 55`.

## Repository Layout

| Path | Description |
| --- | --- |
| `src/` | CPU RTL source files |
| `tb/` | testbenches |
| `program/` | memory initialization files (`.mem`) |
| `vivado/` | board constraint file |
| `doc/` | handoff notes and report-related docs |

## Implemented Modules

- `cpu_top.v`: single-cycle RV32I-subset CPU
- `pipeline_cpu_top.v`: 5-stage pipeline CPU framework
- `minisys_top.v`: board-level top module for `Minisys`

## Supported Instructions

```text
add, sub, and, or
addi
lw, sw
beq
jal
```

## Verified Board Mapping

The current `vivado/minisys_template.xdc` is already updated for the `Minisys` board used in this project:

- `clk` -> `Y18` (100 MHz)
- `rst_btn` -> `P20` (`S6`, active high)
- `led[7:0]` -> red LEDs `RLD0~RLD7`

Board-level output:

```text
led = debug_dmem0[7:0]
```

So when the basic program finishes with `dmem[0] = 55`, the red LEDs show:

```text
00110111
```

## Important Vivado Note

Instruction memory is loaded through `$readmemh`.

This repository uses:

```verilog
.INIT_FILE("sum.mem")
```

That means `program/sum.mem` must be added into the Vivado project before simulation or synthesis.

If Vivado reports it cannot open `sum.mem`:

1. Add `program/sum.mem` to the project
2. Re-run simulation or synthesis
3. Check logs for `$readmemh` warnings

If `sum.mem` is missing during synthesis, the board may program successfully but all LEDs stay off because `imem` is empty.

## Basic Verification Flow

### Simulation

Use:

- `tb/tb_single_cycle.v`

Expected result:

```text
PASS: single-cycle sum dmem[0]=55
```

### Board Test

1. Build bitstream with `minisys_top` as top module
2. Program device through Vivado Hardware Manager
3. Press and release `S6` if needed
4. Check red LEDs

Expected LED value:

```text
00110111
```

## Recommended Next Step

After the single-cycle version is stable, move to pipeline verification:

1. Run `tb_pipeline.v`
2. Verify `hazard.mem`
3. Verify `load_use.mem`
4. Verify `branch.mem`
5. Only then move the pipeline version to board-level testing

## Handoff

See:

- [doc/handoff_status.md](doc/handoff_status.md)

That file records:

- verified board pins
- current stable status
- known Vivado path issue around `sum.mem`
- recommended Git workflow for handoff
