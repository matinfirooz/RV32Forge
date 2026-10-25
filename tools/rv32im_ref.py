#!/usr/bin/env python3
"""Architectural RV32IM model for RV32Forge's documented execution environment.

No timing model. ECALL is a terminal marker; faults halt instead of vectoring.
The retire log supports instruction-by-instruction RTL differential checking.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
MASK = 0xffffffff

def u32(x): return x & MASK

def s32(x):
    x &= MASK
    return x-(1<<32) if x & (1<<31) else x

def sext(v,bits):
    v &= (1<<bits)-1
    return v-(1<<bits) if v & (1<<(bits-1)) else v

def divs(a,b):
    a,b=s32(a),s32(b)
    if b==0: return MASK
    q=abs(a)//abs(b)
    return u32(-q if (a<0)!=(b<0) else q)

def rems(a,b):
    if b==0: return u32(a)
    # s32(DIV_MIN/-1) wraps, but the remainder is still exactly zero.
    a,b=s32(a),s32(b)
    q=abs(a)//abs(b)
    if (a<0)!=(b<0): q=-q
    return u32(a-q*b)

def mulh_ss(a,b): return u32((s32(a)*s32(b))>>32)
def mulh_su(a,b): return u32((s32(a)*u32(b))>>32)
def mulh_uu(a,b): return u32((u32(a)*u32(b))>>32)

def legal(ins):
    op=ins&127; f3=(ins>>12)&7; f7=ins>>25
    if op==0x33: return f7 in (0,1) or (f7==32 and f3 in (0,5))
    if op==0x13:
        return (f7==0 if f3==1 else f7 in (0,32) if f3==5 else True)
    if op==3: return f3 in (0,1,2,4,5)
    if op==0x23: return f3 in (0,1,2)
    if op==0x63: return f3 in (0,1,4,5,6,7)
    if op==0x67: return f3==0
    if op in (0x17,0x37,0x6f): return True
    if op==0x0f: return f3==0
    if op==0x73: return ins in (0x73,0x100073)
    return False

class CPU:
    def __init__(self,words,mem_bytes=65536):
        self.imem=list(words); self.mem=bytearray(mem_bytes)
        self.x=[0]*32; self.pc=0; self.steps=0; self.halted=False
        self.faulted=False; self.fault_cause=0; self.fault_pc=0
        self.trace=[]; self.uart=bytearray()

    def load(self,a,n):
        if 0 <= a <= len(self.mem)-n: return int.from_bytes(self.mem[a:a+n],'little')
        return 0

    def load32(self,a): return self.load(a,4)

    def store(self,a,v,n):
        if 0 <= a <= len(self.mem)-n:
            self.mem[a:a+n]=(v&((1<<(8*n))-1)).to_bytes(n,'little')
        elif a==0x10000000: self.uart.append(v&255)

    def step(self):
        if self.halted: raise RuntimeError('cannot step a halted CPU')
        if self.pc&3: raise RuntimeError(f'unaligned instruction fetch {self.pc:#x}')
        idx=self.pc//4; ins=self.imem[idx] if idx<len(self.imem) else 0x13
        pc0=self.pc; next_pc=u32(pc0+4); self.steps+=1
        op=ins&127; rd=(ins>>7)&31; f3=(ins>>12)&7
        rs1=(ins>>15)&31; rs2=(ins>>20)&31; f7=ins>>25
        a,b=self.x[rs1],self.x[rs2]; wr=None
        ii=sext(ins>>20,12)
        si=sext(((ins>>25)<<5)|((ins>>7)&31),12)
        bi=sext(((ins>>31)<<12)|(((ins>>7)&1)<<11)|(((ins>>25)&63)<<5)|(((ins>>8)&15)<<1),13)
        ji=sext(((ins>>31)<<20)|(((ins>>12)&255)<<12)|(((ins>>20)&1)<<11)|(((ins>>21)&1023)<<1),21)
        ev={'pc':pc0,'instr':ins,'rd':0,'wdata':0,'mem_we':False,
            'mem_addr':0,'mem_wdata':0,'mem_size':0,'stop':False,'fault':False,'cause':0}
        fault=None
        if not legal(ins): fault=2
        elif ins==0x100073: fault=3
        elif ins==0x73: ev['stop']=True
        elif op==0x33:
            if f7==1:
                wr=[lambda:u32(a*b),lambda:mulh_ss(a,b),lambda:mulh_su(a,b),lambda:mulh_uu(a,b),
                    lambda:divs(a,b),lambda:MASK if b==0 else a//b,
                    lambda:rems(a,b),lambda:a if b==0 else a%b][f3]()
            else:
                wr=[lambda:a-b if f7==32 else a+b,lambda:a<<(b&31),
                    lambda:int(s32(a)<s32(b)),lambda:int(a<b),lambda:a^b,
                    lambda:s32(a)>>(b&31) if f7==32 else a>>(b&31),lambda:a|b,lambda:a&b][f3]()
        elif op==0x13:
            sh=(ins>>20)&31
            wr=[lambda:a+ii,lambda:a<<sh,lambda:int(s32(a)<ii),lambda:int(a<u32(ii)),
                lambda:a^u32(ii),lambda:s32(a)>>sh if f7==32 else a>>sh,
                lambda:a|u32(ii),lambda:a&u32(ii)][f3]()
        elif op in (3,0x23):
            store=(op==0x23); addr=u32(a+(si if store else ii)); size=f3&3; n=1<<size
            if addr&(n-1): fault=6 if store else 4
            elif store:
                self.store(addr,b,n)
                ev.update(mem_we=True,mem_addr=addr,mem_wdata=b,mem_size=size)
            else:
                value=self.load(addr,n)
                wr=sext(value,8*n) if f3<4 else value
        elif op==0x63:
            take={0:a==b,1:a!=b,4:s32(a)<s32(b),5:s32(a)>=s32(b),6:a<b,7:a>=b}[f3]
            if take: next_pc=u32(pc0+bi)
        elif op==0x6f: wr=next_pc; next_pc=u32(pc0+ji)
        elif op==0x67: wr=next_pc; next_pc=u32(a+ii)&~1
        elif op==0x37: wr=ins&0xfffff000
        elif op==0x17: wr=u32(pc0+(ins&0xfffff000))
        # FENCE: all memory operations already complete in order.
        if next_pc&3: fault=0
        if fault is not None:
            ev.update(stop=True,fault=True,cause=fault,rd=0,wdata=0,mem_we=False)
            self.faulted=True; self.fault_cause=fault; self.fault_pc=pc0
        elif wr is not None and rd:
            self.x[rd]=u32(wr); ev.update(rd=rd,wdata=u32(wr))
        self.x[0]=0
        if ev['stop']: self.halted=True; self.fault_pc=pc0
        self.pc=next_pc; self.trace.append(ev)
        return ev

    def run(self,max_steps=100000):
        while not self.halted and self.steps<max_steps: self.step()
        if not self.halted: raise RuntimeError('program did not halt')
        return self.trace

def words(path):
    return [int(x.split('//',1)[0].strip(),16) for x in Path(path).read_text().splitlines()
            if x.split('//',1)[0].strip()]

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('hex'); ap.add_argument('--max-steps',type=int,default=100000)
    ap.add_argument('--trace',type=Path); args=ap.parse_args()
    c=CPU(words(args.hex)); c.run(args.max_steps)
    if args.trace: args.trace.write_text(''.join(json.dumps(e)+'\n' for e in c.trace))
    print(f'PASS: {c.steps} architectural events; fault={c.faulted}, cause={c.fault_cause}')
    for a in range(0x100,0x1c4,4):
        v=c.load32(a)
        if v: print(f'mem[{a:#05x}] = 0x{v:08x} ({s32(v)})')
if __name__=='__main__': main()
