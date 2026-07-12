#!/usr/bin/env python3
"""Generate trap_inspect_board.mem — interrupt inspection test.

This program stores diagnostic values to DMEM so they can be read
via the 7-segment display (DISPLAY_DMEM mode, sw[7:0] = address).

DMEM layout:
  [0]  = ISR entry flag (0xFF)
  [1]  = captured x1/ra  shadow (expect 0xA1)
  [2]  = captured x5/t0  shadow (expect 0xB5)
  [3]  = captured x6/t1  shadow (expect 0xC6)
  [4]  = captured x7/t2  shadow (expect 0xD7)
  [5]  = restored x1 after MRET  (expect 0xA1)
  [6]  = restored x5 after MRET  (expect 0xB5)
  [7]  = restored x6 after MRET  (expect 0xC6)
  [8]  = restored x7 after MRET  (expect 0xD7)
  [16] = mtvec  readback (expect 0x100)
  [17] = mie    readback (expect 0x880)
  [18] = mstatus readback (expect 0x8)
  [19] = mtime sample #1 (should be non-zero)
  [20] = mtime sample #2 (should be > sample #1)

LED timeline: 0x0F → 0xF0 → [binary] → 0xFF(ISR!) → 0xAA(PASS)
"""

# ===================================================================
# RISC-V instruction encoders
# ===================================================================
def R(f7, rs2, rs1, f3, rd, op): return (f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def I(imm12, rs1, f3, rd, op):    return ((imm12&0xFFF)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def S(imm12, rs2, rs1, f3, op):
    return ((imm12>>5)<<25)|((imm12&0x1F)<<7)|(rs2<<20)|(rs1<<15)|(f3<<12)|op
def U(imm20, rd, op):             return (imm20<<12)|(rd<<7)|op

def B(off, rs2, rs1, f3, op):
    o = (off >> 1) & 0xFFF
    return (((o>>11)&1)<<31 | ((o>>4)&0x3F)<<25 | rs2<<20 |
            rs1<<15 | f3<<12 | (o&0xF)<<8 | ((o>>10)&1)<<7 | op)

def J(off, rd, op):
    o = (off >> 1) & 0xFFFFF
    return (((o>>19)&1)<<31 | ((o>>0)&0x3FF)<<21 | ((o>>10)&1)<<20 |
            ((o>>11)&0xFF)<<12 | rd<<7 | op)

# Opcodes
O_LUI=0x37; O_JAL=0x6F; O_BR=0x63; O_LD=0x03; O_ST=0x23
O_AI=0x13; O_ALU=0x33; O_SYS=0x73

# Mnemonics
NOP = I(0,0,0,0,O_AI)
def ADDI(rd,rs1,imm): return I(imm&0xFFF,rs1,0,rd,O_AI)
def SRLI(rd,rs1,sh):  return I(sh&0x1F,rs1,5,rd,O_AI)
def LUI(rd,imm):      return U(imm&0xFFFFF,rd,O_LUI)
def SW(rs2,off,rs1):  return S(off&0xFFF,rs2,rs1,2,O_ST)
def LW(rd,off,rs1):   return I(off&0xFFF,rs1,2,rd,O_LD)
def ADD(rd,rs1,rs2):  return R(0,rs2,rs1,0,rd,O_ALU)
def SUB(rd,rs1,rs2):  return R(0x20,rs2,rs1,0,rd,O_ALU)
def BEQ(rs1,rs2,off): return B(off,rs2,rs1,0,O_BR)
def BNE(rs1,rs2,off): return B(off,rs2,rs1,1,O_BR)
def BLTU(rs1,rs2,off):return B(off,rs2,rs1,6,O_BR)
def JAL(rd,off):       return J(off,rd,O_JAL)
def CSRRW(rd,csr,rs1): return I(csr&0xFFF,rs1,1,rd,O_SYS)
def CSRRS(rd,csr,rs1): return I(csr&0xFFF,rs1,2,rd,O_SYS)
def MRET():            return (0x18<<25)|(2<<20)|0x73

# Registers
x0,ra,sp,gp,tp = 0,1,2,3,4
t0,t1,t2       = 5,6,7
s0,s1          = 8,9
t3,t4,t5,t6    = 28,29,30,31

CSR_MSTATUS = 0x300
CSR_MTVEC   = 0x305
CSR_MIE     = 0x304
CSR_MEPC    = 0x341
CSR_MCAUSE  = 0x342

# 100 MHz → 10 ns/tick
T_500ms = 50_000_000
T_100ms = 10_000_000
T_100K  = 100_000

def hi20(n): return (n >> 12) & 0xFFFFF
def lo12(n): return n & 0xFFF

def load_imm(rd, imm):
    """Load 32-bit immediate into rd.
    Handles ADDI sign-extension quirk when bit 11 of lower is set."""
    upper = (imm >> 12) & 0xFFFFF
    lower = imm & 0xFFF
    if lower & 0x800:          # bit 11 set → ADDI will sign-extend negative
        upper = (upper + 1) & 0xFFFFF   # compensate by adding 1 to LUI portion
    result = []
    if upper != 0:
        result.append(LUI(rd, upper))
    if lower != 0 or upper == 0:
        result.append(ADDI(rd, rd if upper != 0 else x0, lower))
    return result

words = []
def EMIT(w): words.append(w)
def ADDR():  return len(words) * 4

# ═══════════════════════════════════════════════════════════════════
# Phase 1: LED = 0x0F for ~500ms  (quick visual: "program loaded")
# ═══════════════════════════════════════════════════════════════════
EMIT(LUI(t5, 0x10000))              # t5 = 0x10000000 (LED base)
EMIT(ADDI(t6, x0, 0x0F))            # t6 = 0x0F
EMIT(SW(t6, 0, t5))                 # LED = 0x0F

EMIT(LUI(t3, 0x10000))
EMIT(ADDI(t3, t3, 0x100))           # t3 = MTIME (0x10000100)
EMIT(LW(t4, 0, t3))                 # t4 = current mtime
EMIT(LUI(t6, hi20(T_500ms)))
EMIT(ADDI(t6, t6, lo12(T_500ms)))
EMIT(ADD(t4, t4, t6))               # target = mtime + 500ms
W1 = ADDR()
EMIT(LW(t6, 0, t3))                 # poll mtime
EMIT(BLTU(t6, t4, W1 - ADDR()))     # wait

# ═══════════════════════════════════════════════════════════════════
# Phase 2: LED = 0xF0 for ~500ms  (quick visual: "running")
# ═══════════════════════════════════════════════════════════════════
EMIT(ADDI(t6, x0, 0xF0))
EMIT(SW(t6, 0, t5))                 # LED = 0xF0

EMIT(LUI(t3, 0x10000))
EMIT(ADDI(t3, t3, 0x100))
EMIT(LW(t4, 0, t3))
EMIT(LUI(t6, hi20(T_500ms)))
EMIT(ADDI(t6, t6, lo12(T_500ms)))
EMIT(ADD(t4, t4, t6))
W2 = ADDR()
EMIT(LW(t6, 0, t3))
EMIT(BLTU(t6, t4, W2 - ADDR()))

# ═══════════════════════════════════════════════════════════════════
# Phase 3: CSR write + readback → DMEM[16..18]
# ═══════════════════════════════════════════════════════════════════
# 3a) mtvec = 0x200, read back → DMEM[16]
for inst in load_imm(t6, 0x200):
    EMIT(inst)
EMIT(CSRRW(x0, CSR_MTVEC, t6))      # mtvec = 0x200
EMIT(CSRRS(t4, CSR_MTVEC, x0))      # t4 = mtvec (pure read, rs1=x0)
EMIT(SW(t4, 16*4, x0))              # DMEM[16] = mtvec  (expect 0x100)

# 3b) mie = 0x880 (MTIE | MEIE), read back → DMEM[17]
for inst in load_imm(t6, 0x880):
    EMIT(inst)
EMIT(CSRRW(x0, CSR_MIE, t6))        # mie = 0x880
EMIT(CSRRS(t4, CSR_MIE, x0))        # t4 = mie
EMIT(SW(t4, 17*4, x0))              # DMEM[17] = mie  (expect 0x880)

# 3c) mstatus = 0x8 (MIE), read back → DMEM[18]
EMIT(ADDI(t6, x0, 8))
EMIT(CSRRW(x0, CSR_MSTATUS, t6))    # mstatus = 8
EMIT(CSRRS(t4, CSR_MSTATUS, x0))    # t4 = mstatus
EMIT(SW(t4, 18*4, x0))              # DMEM[18] = mstatus  (expect 0x8)

# ═══════════════════════════════════════════════════════════════════
# Phase 4: mtime counter check → DMEM[19..20]
# Read mtime at two points separated by ~100K cycles.
# DMEM[20] should be visibly larger than DMEM[19].
# ═══════════════════════════════════════════════════════════════════
EMIT(LUI(t3, 0x10000))
EMIT(ADDI(t3, t3, 0x100))           # t3 = MTIME (0x10000100)
EMIT(LW(t4, 0, t3))                 # t4 = mtime (sample 1)
EMIT(SW(t4, 19*4, x0))              # DMEM[19] = mtime sample 1

# Wait ~100K ticks
for inst in load_imm(t6, T_100K):
    EMIT(inst)
EMIT(ADD(t4, t4, t6))               # target = mtime + 100K
W4 = ADDR()
EMIT(LW(t6, 0, t3))
EMIT(BLTU(t6, t4, W4 - ADDR()))

# Read mtime again → DMEM[20]
EMIT(LW(t4, 0, t3))
EMIT(SW(t4, 20*4, x0))              # DMEM[20] = mtime sample 2

# ═══════════════════════════════════════════════════════════════════
# Phase 5: Set shadow values + mtimecmp = mtime + 500ms
# ═══════════════════════════════════════════════════════════════════
EMIT(ADDI(ra, x0, 0xA1))            # x1  = 0x0A1 (shadow capture target)
EMIT(ADDI(t0, x0, 0xB5))            # x5  = 0x0B5
EMIT(ADDI(t1, x0, 0xC6))            # x6  = 0x0C6
EMIT(ADDI(t2, x0, 0xD7))            # x7  = 0x0D7

EMIT(LUI(t3, 0x10000))
EMIT(ADDI(t3, t3, 0x100))           # t3 = MTIME
EMIT(LW(t6, 0, t3))                 # read mtime
EMIT(LUI(t4, hi20(T_500ms)))
EMIT(ADDI(t4, t4, lo12(T_500ms)))
EMIT(ADD(t6, t6, t4))               # t6 = mtime + 500ms
EMIT(ADDI(t3, t3, 4))               # t3 = MTIMECMP (0x10000104)
EMIT(SW(t6, 0, t3))                 # mtimecmp = target  → interrupt fires in ~500ms!

# ═══════════════════════════════════════════════════════════════════
# Phase 6: Main loop — LED = mtime[31:24]
#
# CHECK ISR FLAG at top of loop: LW DMEM[0], compare to 0xFF.
# After MRET returns (mepc → somewhere in this loop), the next
# iteration of the loop will see DMEM[0]==0xFF and jump to Phase 7.
#
# Registers NOT shadowed (t3=x28, t5=x30, t6=x31):
#   These are re-initialized each loop iteration so they work
#   correctly even after MRET (which doesn't restore them).
# ═══════════════════════════════════════════════════════════════════
EMIT(LUI(t5, 0x10000))              # reinit LED base (x30, not shadowed)
LOOP = ADDR()

# --- ISR flag check ---
# After MRET returns into this loop, DMEM[0]==0xFF tells us ISR has run.
EMIT(LW(t4, 0, x0))                 # t4 = DMEM[0]
EMIT(ADDI(t3, x0, 0xFF))            # t3 = 0xFF
EMIT(BNE(t4, t3, 8))                # if no ISR yet → skip JAL, go to normal loop
JMP_VERIFY_IDX = len(words)         # remember index for back-patch
EMIT(JAL(x0, 0))                    # placeholder: ISR ran → goto VERIFY (patched below)

# --- Normal loop body (DMEM[0] != 0xFF) ---
EMIT(LUI(t3, 0x10000))              # t3 = 0x10000000  (MTIME base upper)
EMIT(ADDI(t3, t3, 0x100))           # t3 = 0x10000100  (MTIME)
EMIT(LW(t6, 0, t3))                 # t6 = mtime
EMIT(SRLI(t6, t6, 24))              # t6 = mtime[31:24]
EMIT(SW(t6, 0, t5))                 # LED = mtime[31:24]
# Delay padding
EMIT(LW(t6, 0, t3))
EMIT(LW(t6, 0, t3))
EMIT(LW(t6, 0, t3))
EMIT(JAL(x0, LOOP - ADDR()))        # → back to LOOP

# ═══════════════════════════════════════════════════════════════════
# Phase 7: Post-ISR verification  (reached via back-patched JAL)
#
# After MRET, shadow_restore has restored x1/x5/x6/x7.
# Save the RESTORED register values to DMEM[5..8].
# ═══════════════════════════════════════════════════════════════════
VERIFY = ADDR()
# Back-patch the JAL placeholder at JMP_VERIFY_IDX → VERIFY
words[JMP_VERIFY_IDX] = JAL(x0, VERIFY - JMP_VERIFY_IDX * 4)

EMIT(SW(ra, 5*4, x0))              # DMEM[5]  = restored x1 (expect 0xA1)
EMIT(SW(t0, 6*4, x0))              # DMEM[6]  = restored x5 (expect 0xB5)
EMIT(SW(t1, 7*4, x0))              # DMEM[7]  = restored x6 (expect 0xC6)
EMIT(SW(t2, 8*4, x0))              # DMEM[8]  = restored x7 (expect 0xD7)

# LED = 0xAA  ("test PASS")
EMIT(LUI(t5, 0x10000))
EMIT(ADDI(t6, x0, 0xAA))
EMIT(SW(t6, 0, t5))                # LED = 0xAA (PASS!)
DONE = ADDR()
EMIT(JAL(x0, DONE - ADDR()))       # infinite loop (JAL x0, 0)

# Padding to 0x200 (ISR entry)
while ADDR() < 0x200:
    EMIT(NOP)

# ═══════════════════════════════════════════════════════════════════
# ISR Handler (PC 0x100)
#
# 1. LED = 0xFF (marker — ISR fired)
# 2. DMEM[0] = 0xFF (flag — ISR has run)
# 3. Save captured shadow values → DMEM[1..4]
# 4. Destroy x1/x5/x6/x7 (modified values)
# 5. Reset mtimecmp = huge value (won't re-trigger)
# 6. MRET → shadow_restore recovers original register values
# ═══════════════════════════════════════════════════════════════════
ISR = ADDR()

# LED = 0xFF (immediate visible marker)
EMIT(LUI(t5, 0x10000))              # t5 = LED base
EMIT(ADDI(t4, x0, 0xFF))
EMIT(SW(t4, 0, t5))                 # LED = 0xFF

# DMEM[0] = 0xFF (ISR flag — main loop checks this)
EMIT(SW(t4, 0, x0))                 # DMEM[0] = 0xFF

# Hold LED=0xFF for ~100ms (shorter delay for quicker testing)
EMIT(LUI(t3, 0x10000))
EMIT(ADDI(t3, t3, 0x100))           # t3 = MTIME
EMIT(LW(t4, 0, t3))                 # read mtime
EMIT(LUI(t6, hi20(T_100ms)))
EMIT(ADDI(t6, t6, lo12(T_100ms)))
EMIT(ADD(t4, t4, t6))               # target = mtime + 100ms
W_ISR = ADDR()
EMIT(LW(t6, 0, t3))
EMIT(BLTU(t6, t4, W_ISR - ADDR()))  # wait

# Save captured shadow values → DMEM[1..4]
EMIT(SW(ra, 1*4, x0))               # DMEM[1] = captured x1 (expect 0xA1)
EMIT(SW(t0, 2*4, x0))               # DMEM[2] = captured x5 (expect 0xB5)
EMIT(SW(t1, 3*4, x0))               # DMEM[3] = captured x6 (expect 0xC6)
EMIT(SW(t2, 4*4, x0))               # DMEM[4] = captured x7 (expect 0xD7)

# Destroy regs (these will be restored by shadow_restore on MRET)
EMIT(ADDI(ra, x0, 0xDE))
EMIT(ADDI(t0, x0, 0xAD))
EMIT(ADDI(t1, x0, 0xBE))
EMIT(ADDI(t2, x0, 0xEF))

# Reset mtimecmp to huge value (won't trigger again any time soon)
EMIT(LUI(t3, 0x10000))
EMIT(ADDI(t3, t3, 0x104))           # t3 = MTIMECMP
EMIT(LUI(t6, 0x7FFFF))              # t6 = 0x7FFFF000
EMIT(SW(t6, 0, t3))                 # mtimecmp = 0x7FFFF000

EMIT(MRET())                         # shadow_restore: x1,x5,x6,x7 restored!

# ═══════════════════════════════════════════════════════════════════
# Output
# ═══════════════════════════════════════════════════════════════════
print(f"// trap_inspect_board.mem — auto-generated, {len(words)} words, ISR @0x{ISR:03X}")
print(f"// VERIFY @0x{VERIFY:03X}  |  main loop @0x{LOOP:03X}")
print(f"// DMEM layout:")
print(f"//   [0]=ISR_flag [1..4]=captured_shadows [5..8]=restored_shadows")
print(f"//   [16]=mtvec [17]=mie [18]=mstatus [19..20]=mtime_samples")
print()
for w in words:
    print(f"{w:08X}")
