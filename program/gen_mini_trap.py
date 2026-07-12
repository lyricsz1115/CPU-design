#!/usr/bin/env python3
"""Generate mini_trap.mem — minimum interrupt test for board verification.

LED: 0x55(setup) → 0x66(loop) → 0xFF(ISR!) → 0xAA(PASS)
DMEM: [0]=captured x1 (expect 5A)  [1]=restored x1 (expect 5A)

Key: ISR address is computed dynamically and back-patched into mtvec setup.
"""

def I(i12,rs1,f3,rd,op):  return ((i12&0xFFF)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def S(i12,rs2,rs1,f3,op): return ((i12>>5)<<25)|((i12&0x1F)<<7)|(rs2<<20)|(rs1<<15)|(f3<<12)|op
def U(i20,rd,op):          return (i20<<12)|(rd<<7)|op
def B(off,rs2,rs1,f3,op):
    o=(off>>1)&0xFFF
    return ((o>>11)&1)<<31|((o>>4)&0x3F)<<25|rs2<<20|rs1<<15|f3<<12|(o&0xF)<<8|((o>>10)&1)<<7|op
def J(off,rd,op):
    o=(off>>1)&0xFFFFF
    return ((o>>19)&1)<<31|(o&0x3FF)<<21|((o>>10)&1)<<20|((o>>11)&0xFF)<<12|rd<<7|op

O_L=0x37; O_J=0x6F; O_B=0x63; O_LD=0x03; O_ST=0x23; O_AI=0x13; O_S=0x73

w=[]
def E(x): w.append(x)
def A(): return len(w)*4

x0,ra=0,1; t3,t4,t5,t6=28,29,30,31

def LUI(rd,imm):       return U(imm&0xFFFFF,rd,O_L)
def ADDI(rd,rs1,imm):  return I(imm&0xFFF,rs1,0,rd,O_AI)
def SRLI(rd,rs1,sh):   return I(sh&0x1F,rs1,5,rd,O_AI)
def SW(rs2,off,rs1):   return S(off&0xFFF,rs2,rs1,2,O_ST)
def LW(rd,off,rs1):    return I(off&0xFFF,rs1,2,rd,O_LD)
def BNE(rs1,rs2,off):  return B(off,rs2,rs1,1,O_B)
def JAL(rd,off):       return J(off,rd,O_J)
def CSRRW(rd,csr,rs1): return I(csr&0xFFF,rs1,1,rd,O_S)
def MRET():            return (0x18<<25)|(2<<20)|O_S

# ─── 0x00: LED=0x55 ───
E(LUI(t6,0x10000)); E(ADDI(t4,x0,0x55)); E(SW(t4,0,t6))

# ─── 0x0C: mtvec = ISR (back-patched) ───
MTVEC_ADDI = len(w);  E(ADDI(t6,x0,0))      # placeholder imm
MTVEC_CSRR = len(w);  E(CSRRW(x0,0x305,t6))

# ─── mie=0x80, mstatus=8 ───
E(ADDI(t6,x0,0x80));   E(CSRRW(x0,0x304,t6))
E(ADDI(t6,x0,8));      E(CSRRW(x0,0x300,t6))

# ─── shadow value + arm timer ───
E(ADDI(ra,x0,0x5A))
E(LUI(t3,0x10000)); E(ADDI(t3,t3,0x100)); E(LW(t4,0,t3))
E(ADDI(t4,t4,0x100)); E(ADDI(t3,t3,4)); E(SW(t4,0,t3))

# ─── main loop ───
LOOP=A()
E(LUI(t6,0x10000)); E(LUI(t4,0x10000)); E(ADDI(t4,t4,0x100))
E(LW(t5,0,t4)); E(SRLI(t5,t5,24)); E(SW(t5,0,t6))
E(LW(t4,0,x0)); E(BNE(t4,x0,8)); E(JAL(x0,LOOP-(A()+4)))

# ─── VERIFY ───
VERIFY=A()
E(SW(ra,4,x0)); E(ADDI(t4,x0,0xAA)); E(SW(t4,0,t6))
DONE=A(); E(JAL(x0,0))

# ─── ISR (starts right after VERIFY, address back-patched into mtvec) ───
ISR=A()
# Back-patch: ADDI t6, x0, ISR
w[MTVEC_ADDI] = ADDI(t6, x0, ISR)

# ─── ISR body ───
E(LUI(t4,0x10000))                    # LED base
E(ADDI(t5,x0,0xFF)); E(SW(t5,0,t4))  # LED=0xFF

E(SW(ra,0,x0))                        # DMEM[0]=captured x1

E(LUI(t3,0x10000)); E(ADDI(t3,t3,0x104))  # MTIMECMP
E(LUI(t5,0x7FFFF)); E(SW(t5,0,t3))       # mtimecmp=0x7FFFF000 (won't re-trigger)

E(ADDI(ra,x0,0xDE))                   # destroy x1
E(MRET())                              # shadow_restore → x1=0x5A

print(f"// mini_trap.mem v3 — {len(w)} words, ISR@0x{ISR:03X}, VERIFY@0x{VERIFY:03X}")
print(f"// LED: 0x55 → 0x66 → 0xFF(ISR!) → 0xAA(PASS)")
print(f"// DMEM[0]=captured x1 (expect 0x5A)  DMEM[1]=restored x1 (expect 0x5A)")
print()
for x in w:
    print(f"{x:08X}")
