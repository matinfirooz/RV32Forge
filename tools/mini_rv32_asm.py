#!/usr/bin/env python3
"""Dependency-free RV32IM assembler with checked encodings and source diagnostics.

U immediates use the standard 20-bit field convention: lui a0,0x12345.
Branch/jump labels are PC-relative; numeric targets are byte displacements.
"""
from __future__ import annotations
import argparse
import re
from pathlib import Path

REGS = {f'x{i}': i for i in range(32)}
REGS.update(dict(zip(
    'zero ra sp gp tp t0 t1 t2 s0 s1 a0 a1 a2 a3 a4 a5 a6 a7 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 t3 t4 t5 t6'.split(),
    range(32))))
REGS['fp'] = 8
RMAP = {'add':(0,0),'sub':(32,0),'sll':(0,1),'slt':(0,2),'sltu':(0,3),
        'xor':(0,4),'srl':(0,5),'sra':(32,5),'or':(0,6),'and':(0,7),
        'mul':(1,0),'mulh':(1,1),'mulhsu':(1,2),'mulhu':(1,3),
        'div':(1,4),'divu':(1,5),'rem':(1,6),'remu':(1,7)}
IMAP = {'addi':0,'slti':2,'sltiu':3,'xori':4,'ori':6,'andi':7}
BMAP = {'beq':0,'bne':1,'blt':4,'bge':5,'bltu':6,'bgeu':7}

class AssemblyError(ValueError):
    pass

def reg(x):
    try: return REGS[x.lower()]
    except KeyError: raise AssemblyError(f'unknown register {x!r}') from None

def imm(x):
    try: return int(x, 0)
    except ValueError: raise AssemblyError(f'expected integer, got {x!r}') from None

def checked(v, bits, name='immediate'):
    if not -(1 << (bits-1)) <= v < (1 << (bits-1)):
        raise AssemblyError(f'{name} {v} is outside signed {bits}-bit range')
    return v

def R(f7, rs2, rs1, f3, rd, opc=0x33):
    return (f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|opc

def I(v, rs1, f3, rd, opc):
    return ((v&0xfff)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|opc

def S(v, rs2, rs1, f3, opc=0x23):
    v &= 0xfff
    return ((v>>5)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((v&31)<<7)|opc

def B(v, rs2, rs1, f3, opc=0x63):
    v &= 0x1fff
    return (((v>>12)&1)<<31)|(((v>>5)&63)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(((v>>1)&15)<<8)|(((v>>11)&1)<<7)|opc

def U(v, rd, opc):
    return ((v&0xfffff)<<12)|(rd<<7)|opc

def J(v, rd, opc=0x6f):
    v &= 0x1fffff
    return (((v>>20)&1)<<31)|(((v>>1)&1023)<<21)|(((v>>11)&1)<<20)|(((v>>12)&255)<<12)|(rd<<7)|opc

def tokenize(line):
    return [x for x in re.split(r'[\s,()]+', line.strip()) if x]

def expand(t):
    op, *a = t
    op = op.lower()
    if op == 'li' and len(a) == 2:
        v = imm(a[1])
        if not -(1<<31) <= v < (1<<32):
            raise AssemblyError('li value must fit 32 bits')
        if v >= 1<<31: v -= 1<<32
        if -2048 <= v <= 2047: return [['addi',a[0],'zero',str(v)]]
        low = ((v+2048)&4095)-2048
        return [['lui',a[0],str(((v+2048)>>12)&0xfffff)],
                ['addi',a[0],a[0],str(low)]]
    if op == 'nop' and not a: return [['addi','zero','zero','0']]
    if op == 'ret' and not a: return [['jalr','zero','ra','0']]
    if op == 'j' and len(a) == 1: return [['jal','zero',a[0]]]
    if op == 'mv' and len(a) == 2: return [['addi',a[0],a[1],'0']]
    if op == 'not' and len(a) == 2: return [['xori',a[0],a[1],'-1']]
    if op == 'neg' and len(a) == 2: return [['sub',a[0],'zero',a[1]]]
    if op in ('beqz','bnez') and len(a) == 2:
        return [['beq' if op == 'beqz' else 'bne',a[0],'zero',a[1]]]
    return [[op]+a]

def encode(t, pc, labels):
    op, *a = t
    count = 3 if op in RMAP or op in IMAP or op in BMAP or op in (
        'slli','srli','srai','lb','lh','lw','lbu','lhu','sb','sh','sw','jalr') else (
        2 if op in ('jal','lui','auipc') else 1 if op == '.word' else 0)
    if len(a) != count: raise AssemblyError(f'{op} expects {count} operands, got {len(a)}')
    def displacement(x, bits):
        if x in labels: v = labels[x]-pc
        else:
            try: v = int(x,0)
            except ValueError: raise AssemblyError(f'unknown label {x!r}') from None
        checked(v,bits,'displacement')
        if v & 1: raise AssemblyError('branch/jump displacement must be even')
        return v
    if op in RMAP:
        f7,f3=RMAP[op]; return R(f7,reg(a[2]),reg(a[1]),f3,reg(a[0]))
    if op in IMAP: return I(checked(imm(a[2]),12),reg(a[1]),IMAP[op],reg(a[0]),0x13)
    if op in ('slli','srli','srai'):
        sh=imm(a[2])
        if not 0 <= sh <= 31: raise AssemblyError('shift amount must be 0..31')
        return I(sh | (0x400 if op=='srai' else 0),reg(a[1]),1 if op=='slli' else 5,reg(a[0]),0x13)
    if op in ('lb','lh','lw','lbu','lhu'):
        return I(checked(imm(a[1]),12),reg(a[2]),{'lb':0,'lh':1,'lw':2,'lbu':4,'lhu':5}[op],reg(a[0]),3)
    if op in ('sb','sh','sw'):
        return S(checked(imm(a[1]),12),reg(a[0]),reg(a[2]),{'sb':0,'sh':1,'sw':2}[op])
    if op in BMAP: return B(displacement(a[2],13),reg(a[1]),reg(a[0]),BMAP[op])
    if op == 'jal': return J(displacement(a[1],21),reg(a[0]))
    if op == 'jalr': return I(checked(imm(a[2]),12),reg(a[1]),0,reg(a[0]),0x67)
    if op in ('lui','auipc'):
        v=imm(a[1])
        if not -(1<<19) <= v < (1<<20): raise AssemblyError('U immediate must be a 20-bit field')
        return U(v,reg(a[0]),0x37 if op=='lui' else 0x17)
    if op == 'ecall': return 0x73
    if op == 'ebreak': return 0x100073
    if op == 'fence': return 0x0ff0000f
    if op == '.word':
        v=imm(a[0])
        if not -(1<<31) <= v < (1<<32): raise AssemblyError('.word value must fit 32 bits')
        return v & 0xffffffff
    raise AssemblyError(f'unsupported instruction {op!r}')

def assemble(src):
    labels, cooked, pc = {}, [], 0
    for number, raw in enumerate(src.splitlines(),1):
        line=raw.split('#',1)[0].split('//',1)[0].strip()
        if not line: continue
        try:
            while ':' in line:
                label,line=line.split(':',1); label=label.strip(); line=line.strip()
                if not re.fullmatch(r'[A-Za-z_.$][\w.$]*',label): raise AssemblyError('invalid label')
                if label in labels: raise AssemblyError(f'duplicate label {label!r}')
                labels[label]=pc
            if not line: continue
            t=tokenize(line)
            if t[0] in ('.text','.globl','.global'): continue
            for expanded in expand(t):
                cooked.append((pc,expanded,number,raw.strip())); pc+=4
        except AssemblyError as e: raise AssemblyError(f'line {number}: {e}: {raw.strip()}') from None
    out=[]
    for pc,t,number,raw in cooked:
        try: out.append(encode(t,pc,labels)&0xffffffff)
        except AssemblyError as e: raise AssemblyError(f'line {number}: {e}: {raw}') from None
    return out

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('source',type=Path); ap.add_argument('output',type=Path)
    args=ap.parse_args()
    try: words=assemble(args.source.read_text())
    except AssemblyError as e: ap.exit(1,f'{args.source}: {e}\n')
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(''.join(f'{w:08x}\n' for w in words))
    print(f'assembled {len(words)} instructions -> {args.output}')
if __name__=='__main__': main()
