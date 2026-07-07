# CPU-design Handoff

## Current Status

- Basic requirement is complete on `Minisys`.
- `cpu_top` single-cycle CPU passes simulation with `sum.mem`.
- Board-level test passes on `Minisys` and shows `00110111` on the red LEDs.
- `00110111` is `0x37`, which is decimal `55`, matching `dmem[0] = 55`.

## Known Good Board Setup

- FPGA: `xc7a100tfgg484-1`
- Clock pin: `Y18`, 100 MHz
- Reset button: `S6` -> FPGA pin `P20`, active high
- LEDs used: red LEDs `RLD0~RLD7`
  - `led[0]` -> `N19`
  - `led[1]` -> `N20`
  - `led[2]` -> `M20`
  - `led[3]` -> `K13`
  - `led[4]` -> `K14`
  - `led[5]` -> `M13`
  - `led[6]` -> `L13`
  - `led[7]` -> `K17`

Relevant files:

- [src/minisys_top.v](../src/minisys_top.v)
- [vivado/minisys_template.xdc](../vivado/minisys_template.xdc)

## Important Path Note

`imem.v` loads the program with `$readmemh`.

To avoid machine-specific absolute paths, `tb_single_cycle.v` and `minisys_top.v` now use:

```verilog
.INIT_FILE("sum.mem")
```

This only works if `program/sum.mem` is added into the Vivado project so Vivado can copy or resolve it during simulation and synthesis.

When creating or reopening the Vivado project, always add:

- `program/sum.mem`

If simulation or synthesis reports it cannot open `sum.mem`, check that:

1. `sum.mem` is present in the project.
2. It is included in the active fileset.
3. The run was restarted after adding the file.

## Verified Basic Flow

### Simulation

- Testbench: [tb/tb_single_cycle.v](../tb/tb_single_cycle.v)
- Expected message:

```text
PASS: single-cycle sum dmem[0]=55
```

### Board Test

- Top module: `minisys_top`
- Program: `sum.mem`
- LED output:

```text
debug_dmem0[7:0] = 8'b00110111
```

If LEDs are all off, first suspect program memory initialization failure.

## Recommended Next Step

Move to pipeline verification, not board changes first.

Suggested order:

1. Run `tb_pipeline.v`
2. Verify `hazard.mem`
3. Verify `load_use.mem`
4. Verify `branch.mem`
5. Only after simulation is stable, switch board top to `pipeline_cpu_top`

## Git Upload Flow

### 1. Check status

```powershell
git status
```

### 2. Review the key files

- `src/minisys_top.v`
- `tb/tb_single_cycle.v`
- `vivado/minisys_template.xdc`
- `doc/handoff_status.md`

Optional:

- Do not commit temporary waveform files unless the team wants them.
- `tb_single_cycle_behav.wcfg` is usually local-only.

### 3. Stage files

```powershell
git add src/minisys_top.v
git add tb/tb_single_cycle.v
git add vivado/minisys_template.xdc
git add doc/handoff_status.md
```

If you do not want the waveform config:

```powershell
git restore --staged tb_single_cycle_behav.wcfg
```

or just do not add it.

### 4. Commit

Example:

```powershell
git commit -m "Finish single-cycle Minisys board bring-up"
```

### 5. Add remote if needed

```powershell
git remote -v
git remote add origin https://github.com/lyricsz1115/CPU-design.git
```

If `origin` already exists but points elsewhere:

```powershell
git remote set-url origin https://github.com/lyricsz1115/CPU-design.git
```

### 6. Push

If the branch is `main`:

```powershell
git push -u origin main
```

If the branch is `master`:

```powershell
git push -u origin master
```

If unsure:

```powershell
git branch
```

## What the Next Person Should Know

- The single-cycle CPU is already verified in both simulation and on the Minisys board.
- The board constraints in `vivado/minisys_template.xdc` are real and usable for the current top-level ports.
- Program memory initialization is the main fragile point in Vivado.
- If `sum.mem` is not added to the project, synthesis can succeed but the board will show all LEDs off because `imem` is empty.
