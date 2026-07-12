#!/usr/bin/env python3
"""Generate trap_test_board.mem — verified RV32I instruction encodings."""

# ===================================================================
# RISC-V instruction encoders
# ===================================================================
def R(f7, rs2, rs1, f3, rd, op): return (f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def I(imm12, rs1, f3, rd, op):    return ((imm12&0xFFF)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def S(imm12, rs2, rs1, f3, op):   return ((imm12>>5)<<25)|((imm12&0x1F)<<7)|(rs2<<20)|(rs1<<15)|(f3<<12)|op
def U(imm20, rd, op):             return (imm20<<12)|(rd<<7)|op

def B(off, rs2, rs1, f3, op):
    """offset[12:1] → inst[31|30:25|11:8|7]"""
    o = (off >> 1) & 0xFFF                # 12-bit offset[12:1]
    return (
        ((o>>11)&1)    << 31 |             # offset[12]  → inst[31]
        ((o>>4 )&0x3F) << 25 |             # offset[10:5] → inst[30:25]
        rs2            << 20 |
        rs1            << 15 |
        f3             << 12 |
        (o&0xF)        << 8  |             # offset[4:1]  → inst[11:8]
        ((o>>10)&1)    << 7  |             # offset[11]  → inst[7]
        op
    )

def J(off, rd, op):
    """offset[20:1] → inst[31|30:21|20|19:12]"""
    o = (off >> 1) & 0xFFFFF              # 20-bit offset[20:1]
    return (
        ((o>>19)&1)    << 31 |             # offset[20]   → inst[31]
        ((o>>0)&0x3FF) << 21 |             # offset[10:1]  → inst[30:21]
        ((o>>10)&1)    << 20 |             # offset[11]   → inst[20]
        ((o>>11)&0xFF) << 12 |             # offset[19:12] → inst[19:12]
        rd             << 7  |
        op
    )

# Opcodes
O_LUI=0x37; O_JAL=0x6F; O_BR=0x63; O_LD=0x03; O_ST=0x23; O_AI=0x13; O_ALU=0x33; O_SYS=0x73

# Mnemonics (registers 0-31)
NOP = I(0,0,0,0,O_AI)
def ADDI(rd,rs1,imm): return I(imm&0xFFF,rs1,0,rd,O_AI)
def SRLI(rd,rs1,sh):  return I(sh&0x1F,rs1,5,rd,O_AI)
def LUI(rd,imm):      return U(imm&0xFFFFF,rd,O_LUI)
def SW(rs2,off,rs1):  return S(off&0xFFF,rs2,rs1,2,O_ST)
def LW(rd,off,rs1):   return I(off&0xFFF,rs1,2,rd,O_LD)
def ADD(rd,rs1,rs2):  return R(0,rs2,rs1,0,rd,O_ALU)
def CSRRW(rd,csr,rs1): return I(csr&0xFFF,rs1,1,rd,O_SYS)
def BNE(rs1,rs2,off):  return B(off,rs2,rs1,1,O_BR)
def BLTU(rs1,rs2,off): return B(off,rs2,rs1,6,O_BR)
def JAL(rd,off):       return J(off,rd,O_JAL)
def MRET():            return (0x18<<25)|(2<<20)|0x73  # funct7=0011000, rs2=00010, op=1110011

# Registers
x0,ra,sp,gp,tp = 0,1,2,3,4
t0,t1,t2       = 5,6,7
s0,s1          = 8,9
t3,t4,t5,t6    = 28,29,30,31

CSR_MSTATUS = 0x300
CSR_MTVEC   = 0x305
CSR_MIE     = 0x304

# 100 MHz → 10 ns/tick
T_3SEC = 300_000_000  # ticks in 3 seconds
T_HALF =  50_000_000  # ticks in 0.5 seconds
T_1SEC = 100_000_000  # ticks in 1 second  (shorter for better debug UX)

def hi20(n): return (n >> 12) & 0xFFFFF   # upper 20 bits for LUI
def lo12(n): return n & 0xFFF             # lower 12 bits for ADDI

words = []
def EMIT(w): words.append(w)
def ADDR():  return len(words) * 4


# ═══════════════════════════════════════════════════════════════════
# Phase 1: LED = 0x0F for ~3s
# ═══════════════════════════════════════════════════════════════════
EMIT(LUI(t5, 0x10000))              # t5 = 0x10000000 (LED base)
EMIT(ADDI(t6, x0, 0x0F))            # t6 = 0x0F
EMIT(SW(t6, 0, t5))                 # LED = 0x0F (低4位亮)

EMIT(LUI(t3, 0x10000))
EMIT(ADDI(t3, t3, 0x100))           # t3 = MTIME addr (0x10000100)
EMIT(LW(t4, 0, t3))                 # t4 = current mtime
EMIT(LUI(t6, hi20(T_3SEC)))         # t6 upper
EMIT(ADDI(t6, t6, lo12(T_3SEC)))    # t6 = 300M ticks
EMIT(ADD(t4, t4, t6))               # t4 = target mtime
W1 = ADDR()
EMIT(LW(t6, 0, t3))                 # poll: read mtime
EMIT(BLTU(t6, t4, W1 - ADDR()))      # wait until mtime >= target

# ═══════════════════════════════════════════════════════════════════
# Phase 2: LED = 0xF0 for ~3s
# ═══════════════════════════════════════════════════════════════════
EMIT(ADDI(t6, x0, 0xF0))            # t6 = 0xF0
EMIT(SW(t6, 0, t5))                 # LED = 0xF0 (高4位亮)

EMIT(LUI(t3, 0x10000))
EMIT(ADDI(t3, t3, 0x100))
EMIT(LW(t4, 0, t3))
EMIT(LUI(t6, hi20(T_3SEC)))
EMIT(ADDI(t6, t6, lo12(T_3SEC)))
EMIT(ADD(t4, t4, t6))
W2 = ADDR()
EMIT(LW(t6, 0, t3))
EMIT(BLTU(t6, t4, W2 - ADDR()))

# ═══════════════════════════════════════════════════════════════════
# Phase 3: CSR setup (enable timer interrupt)
# ═══════════════════════════════════════════════════════════════════
EMIT(ADDI(t6, x0, 0x100))           # handler addr
EMIT(CSRRW(x0, CSR_MTVEC, t6))      # mtvec = 0x100
EMIT(ADDI(t6, x0, CSR_MIE))
EMIT(ADDI(t4, x0, 0x80))            # MTIE (bit 7)
EMIT(CSRRW(x0, CSR_MIE, t4))        # mie = 0x80
EMIT(ADDI(t6, x0, CSR_MSTATUS))
EMIT(ADDI(t4, x0, 8))               # MIE (bit 3)
EMIT(CSRRW(x0, CSR_MSTATUS, t4))    # mstatus = 8 (开中断!)

# ═══════════════════════════════════════════════════════════════════
# Phase 4: Shadow values + mtimecmp = mtime + 0.5s
# ═══════════════════════════════════════════════════════════════════
EMIT(ADDI(ra, x0, 0xA1))              # shadow capture target
EMIT(ADDI(t0, x0, 0xB5))
EMIT(ADDI(t1, x0, 0xC6))
EMIT(ADDI(t2, x0, 0xD7))

EMIT(LUI(t3, 0x10000))
EMIT(ADDI(t3, t3, 0x100))           # t3 = MTIME
EMIT(LW(t6, 0, t3))                 # read mtime
EMIT(LUI(t4, hi20(T_HALF)))
EMIT(ADDI(t4, t4, lo12(T_HALF)))    # t4 = 50M ticks
EMIT(ADD(t6, t4, t6))               # t6 = mtime + 0.5s
EMIT(ADDI(t3, t3, 4))               # t3 = MTIMECMP
EMIT(SW(t6, 0, t3))                 # mtimecmp = target (~0.5s later)

# ═══════════════════════════════════════════════════════════════════
# Phase 5: Main loop — LED = mtime[31:24]
#
# CRITICAL: LUI+ADDI for t3 (MTIME addr) is INSIDE the loop.
# x28 (t3) is NOT a shadow register — the ISR overwrites it with
# the MTIMECMP address.  Re-initializing every iteration ensures
# the loop reads MTIME, not MTIMECMP, even after MRET.
# ═══════════════════════════════════════════════════════════════════
EMIT(LUI(t5, 0x10000))              # restore t5 = LED (x5 IS shadow → MRET restores)
LOOP = ADDR()
EMIT(LUI(t3, 0x10000))              # t3 = MTIME base (re-init every loop!)
EMIT(ADDI(t3, t3, 0x100))           # t3 = 0x10000100
EMIT(LW(t6, 0, t3))                 # LOOP: t6 = mtime
EMIT(SRLI(t6, t6, 24))              # t6 = mtime[31:24] (~3Hz visible)
EMIT(SW(t6, 0, t5))                 # LED = mtime[31:24]
EMIT(LW(t6, 0, t3))                 # delay padding
EMIT(LW(t6, 0, t3))
EMIT(LW(t6, 0, t3))
EMIT(JAL(x0, LOOP - ADDR()))        # → LOOP

# Padding to 0x100 (ISR entry)
while ADDR() < 0x100:
    EMIT(NOP)

# ═══════════════════════════════════════════════════════════════════
# ISR Handler (PC 0x100)
# ═══════════════════════════════════════════════════════════════════
ISR = ADDR()
EMIT(LUI(t5, 0x10000))              # restore LED base
EMIT(ADDI(t4, x0, 0xFF))            # t4 = 0xFF
EMIT(SW(t4, 0, t5))                 # LED = 0xFF !!! ALL LEDS ON !!!
EMIT(SW(t4, 0, x0))                 # dmem[0] = 0xFF

# Hold LED=0xFF for ~5s
EMIT(LUI(t3, 0x10000))
EMIT(ADDI(t3, t3, 0x100))           # t3 = MTIME
EMIT(LW(t4, 0, t3))
EMIT(LUI(t6, hi20(T_1SEC)))
EMIT(ADDI(t6, t6, lo12(T_1SEC)))
EMIT(ADD(t4, t4, t6))
W3 = ADDR()
EMIT(LW(t6, 0, t3))
EMIT(BLTU(t6, t4, W3 - ADDR()))

# Save shadow regs → dmem
EMIT(SW(ra, 4, x0))                 # dmem[1] = ra (expect 0xA1)
EMIT(SW(t0, 8, x0))                 # dmem[2] = t0 (expect 0xB5)
EMIT(SW(t1, 12, x0))                # dmem[3] = t1 (expect 0xC6)
EMIT(SW(t2, 16, x0))                # dmem[4] = t2 (expect 0xD7)

# Destroy regs (shadow targets → restored by MRET)
EMIT(ADDI(ra, x0, 0xDE))
EMIT(ADDI(t0, x0, 0xAD))
EMIT(ADDI(t1, x0, 0xBE))
EMIT(ADDI(t2, x0, 0xEF))

# Reset mtimecmp to huge value (won't trigger again soon)
EMIT(LUI(t3, 0x10000))
EMIT(ADDI(t3, t3, 0x104))           # t3 = MTIMECMP
EMIT(LUI(t6, 0x7FFFF))              # huge
EMIT(SW(t6, 0, t3))

EMIT(MRET())                         # shadow restore x1,x5,x6,x7!

# ═══════════════════════════════════════════════════════════════════
# Output
# ═══════════════════════════════════════════════════════════════════
print(f"// trap_test_board.mem — auto-generated, {len(words)} words, ISR @0x{ISR:03X}")
print()
for w in words:
    print(f"{w:08X}")
