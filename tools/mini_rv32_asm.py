#!/usr/bin/env python3
import re, sys
from pathlib import Path

REGS = {f"x{i}": i for i in range(32)}
REGS.update({
    "zero":0,"ra":1,"sp":2,"gp":3,"tp":4,
    "t0":5,"t1":6,"t2":7,"s0":8,"fp":8,"s1":9,
    "a0":10,"a1":11,"a2":12,"a3":13,"a4":14,"a5":15,"a6":16,"a7":17,
    "s2":18,"s3":19,"s4":20,"s5":21,"s6":22,"s7":23,"s8":24,"s9":25,"s10":26,"s11":27,
    "t3":28,"t4":29,"t5":30,"t6":31
})

def reg(x): return REGS[x.lower()]
def imm(x): return int(x, 0)

def R(f7, rs2, rs1, f3, rd, opc=0x33):
    return (f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|opc
def I(v, rs1, f3, rd, opc):
    v &= 0xfff
    return (v<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|opc
def S(v, rs2, rs1, f3, opc=0x23):
    v &= 0xfff
    return ((v>>5)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((v&0x1f)<<7)|opc
def B(v, rs2, rs1, f3, opc=0x63):
    v &= 0x1fff
    return (((v>>12)&1)<<31)|(((v>>5)&0x3f)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(((v>>1)&0xf)<<8)|(((v>>11)&1)<<7)|opc
def U(v, rd, opc):
    return (v & 0xfffff000) | (rd<<7) | opc
def J(v, rd, opc=0x6f):
    v &= 0x1fffff
    return (((v>>20)&1)<<31)|(((v>>1)&0x3ff)<<21)|(((v>>11)&1)<<20)|(((v>>12)&0xff)<<12)|(rd<<7)|opc

def clean(line):
    line = line.split('#',1)[0].strip()
    return line

def tokenize(line):
    return [x for x in re.split(r'[\s,()]+', line.strip()) if x]

def assemble(src):
    lines = src.splitlines()
    labels = {}
    pc = 0
    cooked = []
    for raw in lines:
        line = clean(raw)
        if not line: continue
        if ':' in line:
            label, rest = line.split(':',1)
            labels[label.strip()] = pc
            line = rest.strip()
            if not line: continue
        cooked.append((pc,line))
        pc += 4

    out=[]
    for pc,line in cooked:
        t=tokenize(line)
        op=t[0].lower()
        a=t[1:]
        w=None

        rmap = {
            "add":(0x00,0),"sub":(0x20,0),"sll":(0x00,1),"slt":(0x00,2),
            "sltu":(0x00,3),"xor":(0x00,4),"srl":(0x00,5),"sra":(0x20,5),
            "or":(0x00,6),"and":(0x00,7),
            "mul":(0x01,0),"mulh":(0x01,1),"mulhsu":(0x01,2),"mulhu":(0x01,3),
            "div":(0x01,4),"divu":(0x01,5),"rem":(0x01,6),"remu":(0x01,7)
        }
        imap = {"addi":0,"slti":2,"sltiu":3,"xori":4,"ori":6,"andi":7}
        bmap = {"beq":0,"bne":1,"blt":4,"bge":5,"bltu":6,"bgeu":7}

        if op in rmap:
            f7,f3=rmap[op]; w=R(f7,reg(a[2]),reg(a[1]),f3,reg(a[0]))
        elif op in imap:
            w=I(imm(a[2]),reg(a[1]),imap[op],reg(a[0]),0x13)
        elif op in ("slli","srli","srai"):
            sh=imm(a[2]) & 31
            f3=1 if op=="slli" else 5
            top=0x20 if op=="srai" else 0x00
            w=I((top<<5)|sh,reg(a[1]),f3,reg(a[0]),0x13)
        elif op in ("lb","lh","lw","lbu","lhu"):
            f3={"lb":0,"lh":1,"lw":2,"lbu":4,"lhu":5}[op]
            # rd, offset(base)
            w=I(imm(a[1]),reg(a[2]),f3,reg(a[0]),0x03)
        elif op in ("sb","sh","sw"):
            f3={"sb":0,"sh":1,"sw":2}[op]
            w=S(imm(a[1]),reg(a[0]),reg(a[2]),f3)
        elif op in bmap:
            target=labels[a[2]]
            w=B(target-pc,reg(a[1]),reg(a[0]),bmap[op])
        elif op=="jal":
            rd=reg(a[0]); target=labels[a[1]]
            w=J(target-pc,rd)
        elif op=="j":
            w=J(labels[a[0]]-pc,0)
        elif op=="jalr":
            w=I(imm(a[2]),reg(a[1]),0,reg(a[0]),0x67)
        elif op=="ret":
            w=I(0,1,0,0,0x67)
        elif op=="lui":
            w=U(imm(a[1]),reg(a[0]),0x37)
        elif op=="auipc":
            w=U(imm(a[1]),reg(a[0]),0x17)
        elif op=="nop":
            w=I(0,0,0,0,0x13)
        elif op=="ecall":
            w=0x00000073
        elif op=="li":
            val=imm(a[1])
            if not -2048 <= val <= 2047:
                raise ValueError("mini assembler li supports only 12-bit immediates")
            w=I(val,0,0,reg(a[0]),0x13)
        else:
            raise ValueError(f"unsupported instruction: {line}")
        out.append(w & 0xffffffff)
    return out

def main():
    if len(sys.argv)!=3:
        print("usage: mini_rv32_asm.py input.s output.hex")
        sys.exit(2)
    words=assemble(Path(sys.argv[1]).read_text())
    Path(sys.argv[2]).write_text("\n".join(f"{w:08x}" for w in words)+"\n")
    print(f"assembled {len(words)} instructions -> {sys.argv[2]}")

if __name__=="__main__":
    main()
