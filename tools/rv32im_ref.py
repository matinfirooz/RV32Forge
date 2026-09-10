#!/usr/bin/env python3
from __future__ import annotations
import argparse
from pathlib import Path

MASK = 0xFFFFFFFF

def u32(x): return x & MASK
def s32(x):
    x &= MASK
    return x - (1 << 32) if x & 0x80000000 else x

def sext(v, bits):
    sign = 1 << (bits - 1)
    return (v ^ sign) - sign

def divs(a, b):
    a, b = s32(a), s32(b)
    if b == 0: return MASK
    if a == -0x80000000 and b == -1: return 0x80000000
    return u32(int(a / b))

def rems(a, b):
    a, b = s32(a), s32(b)
    if b == 0: return u32(a)
    if a == -0x80000000 and b == -1: return 0
    q = int(a / b)
    return u32(a - q * b)

def mulh_ss(a, b):
    return ((s32(a) * s32(b)) & ((1 << 64)-1)) >> 32

def mulh_su(a, b):
    return ((s32(a) * (b & MASK)) & ((1 << 64)-1)) >> 32

def mulh_uu(a, b):
    return (((a & MASK) * (b & MASK)) >> 32) & MASK

class CPU:
    def __init__(self, words):
        self.imem = words
        self.mem = bytearray(65536)
        self.x = [0] * 32
        self.pc = 0
        self.steps = 0
        self.halted = False

    def load32(self, a):
        return int.from_bytes(self.mem[a:a+4], 'little')

    def store(self, a, v, n):
        self.mem[a:a+n] = (v & ((1 << (8*n))-1)).to_bytes(n, 'little')

    def step(self):
        if self.pc % 4: raise RuntimeError(f'unaligned PC {self.pc:#x}')
        idx = self.pc // 4
        ins = self.imem[idx] if 0 <= idx < len(self.imem) else 0x13
        pc0 = self.pc
        self.pc = u32(self.pc + 4)
        self.steps += 1

        opc = ins & 0x7f
        rd = (ins >> 7) & 31
        f3 = (ins >> 12) & 7
        rs1 = (ins >> 15) & 31
        rs2 = (ins >> 20) & 31
        f7 = (ins >> 25) & 0x7f
        a, b = self.x[rs1], self.x[rs2]
        wr = None

        imm_i = sext((ins >> 20) & 0xfff, 12)
        imm_s = sext(((ins >> 25) << 5) | ((ins >> 7) & 0x1f), 12)
        imm_b_bits = (((ins >> 31) & 1) << 12) | (((ins >> 7) & 1) << 11) | (((ins >> 25) & 0x3f) << 5) | (((ins >> 8) & 0xf) << 1)
        imm_b = sext(imm_b_bits, 13)
        imm_j_bits = (((ins >> 31) & 1) << 20) | (((ins >> 12) & 0xff) << 12) | (((ins >> 20) & 1) << 11) | (((ins >> 21) & 0x3ff) << 1)
        imm_j = sext(imm_j_bits, 21)

        if opc == 0x33:
            if f7 == 0x01:
                if f3 == 0: wr = u32((a * b))
                elif f3 == 1: wr = mulh_ss(a, b)
                elif f3 == 2: wr = mulh_su(a, b)
                elif f3 == 3: wr = mulh_uu(a, b)
                elif f3 == 4: wr = divs(a, b)
                elif f3 == 5: wr = MASK if b == 0 else u32((a & MASK) // (b & MASK))
                elif f3 == 6: wr = rems(a, b)
                elif f3 == 7: wr = a if b == 0 else u32((a & MASK) % (b & MASK))
            else:
                if f3 == 0: wr = u32(a - b) if f7 == 0x20 else u32(a + b)
                elif f3 == 1: wr = u32(a << (b & 31))
                elif f3 == 2: wr = int(s32(a) < s32(b))
                elif f3 == 3: wr = int((a & MASK) < (b & MASK))
                elif f3 == 4: wr = a ^ b
                elif f3 == 5: wr = u32(s32(a) >> (b & 31)) if f7 == 0x20 else ((a & MASK) >> (b & 31))
                elif f3 == 6: wr = a | b
                elif f3 == 7: wr = a & b
        elif opc == 0x13:
            if f3 == 0: wr = u32(a + imm_i)
            elif f3 == 2: wr = int(s32(a) < imm_i)
            elif f3 == 3: wr = int((a & MASK) < u32(imm_i))
            elif f3 == 4: wr = a ^ u32(imm_i)
            elif f3 == 6: wr = a | u32(imm_i)
            elif f3 == 7: wr = a & u32(imm_i)
            elif f3 == 1: wr = u32(a << ((ins >> 20) & 31))
            elif f3 == 5:
                sh = (ins >> 20) & 31
                wr = u32(s32(a) >> sh) if ((ins >> 30) & 1) else ((a & MASK) >> sh)
        elif opc == 0x03:
            addr = u32(a + imm_i)
            if f3 == 0: wr = u32(sext(self.mem[addr], 8))
            elif f3 == 1: wr = u32(sext(int.from_bytes(self.mem[addr:addr+2], 'little'), 16))
            elif f3 == 2: wr = self.load32(addr)
            elif f3 == 4: wr = self.mem[addr]
            elif f3 == 5: wr = int.from_bytes(self.mem[addr:addr+2], 'little')
        elif opc == 0x23:
            addr = u32(a + imm_s)
            self.store(addr, b, 1 if f3 == 0 else 2 if f3 == 1 else 4)
        elif opc == 0x63:
            take = {0:a == b, 1:a != b, 4:s32(a)<s32(b), 5:s32(a)>=s32(b), 6:(a&MASK)<(b&MASK), 7:(a&MASK)>=(b&MASK)}.get(f3, False)
            if take: self.pc = u32(pc0 + imm_b)
        elif opc == 0x6f:
            wr = self.pc
            self.pc = u32(pc0 + imm_j)
        elif opc == 0x67:
            wr = self.pc
            self.pc = u32((a + imm_i) & ~1)
        elif opc == 0x37:
            wr = ins & 0xfffff000
        elif opc == 0x17:
            wr = u32(pc0 + (ins & 0xfffff000))
        elif opc == 0x73 and ins == 0x00000073:
            self.halted = True
        else:
            raise RuntimeError(f'unsupported instruction {ins:08x} at {pc0:#x}')

        if wr is not None and rd != 0:
            self.x[rd] = u32(wr)
        self.x[0] = 0

    def run(self, max_steps=100000):
        while not self.halted and self.steps < max_steps:
            self.step()
        if not self.halted:
            raise RuntimeError('program did not halt')

def words(path):
    return [int(line.strip(),16) for line in Path(path).read_text().splitlines() if line.strip()]

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('hex')
    ap.add_argument('--max-steps', type=int, default=100000)
    args=ap.parse_args()
    c=CPU(words(args.hex)); c.run(args.max_steps)
    print(f'PASS: halted after {c.steps} ISA steps')
    for a in range(0x100,0x1a0,4):
        v=c.load32(a)
        if v: print(f'mem[{a:#05x}] = 0x{v:08x} ({s32(v)})')
    if c.load32(0x1c0): print(f'mem[0x1c0] = {c.load32(0x1c0)}')

if __name__=='__main__': main()
