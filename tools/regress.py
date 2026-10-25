#!/usr/bin/env python3
"""Reproducible RTL unit tests and architectural differential regression.

Only Python's standard library plus Icarus Verilog are required.
"""
from __future__ import annotations
import argparse
import csv
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import random
import re
import shlex
import subprocess
import sys
import time
from mini_rv32_asm import assemble
from rv32im_ref import CPU, divs, rems, mulh_ss, mulh_su, mulh_uu, u32, words

ROOT=Path(__file__).resolve().parents[1]
RTL=sorted((ROOT/'rtl').glob('*.sv'))
CONFIGS={'iterative_dynamic':(1,1),'iterative_static':(1,0),'combinational_dynamic':(0,1)}

def run(cmd,log=None):
    p=subprocess.run(cmd,cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120)
    if log: log.write_text(p.stdout)
    if p.returncode:
        raise RuntimeError(f'command failed ({p.returncode}): {shlex.join(map(str,cmd))}\n{p.stdout[-6000:]}')
    return p.stdout

def compile_tb(top,path,params=None,rtl=None):
    cmd=shlex.split(os.environ.get('IVERILOG','iverilog'))+['-g2012','-s',top,'-o',str(path)]
    for k,v in (params or {}).items(): cmd+=['-P',f'{top}.{k}={v}']
    run(cmd+[str(p) for p in (RTL if rtl is None else rtl)]+[str(ROOT/'tb'/f'{top}.sv')],path.with_suffix('.compile.log'))

def simulate(binary,args,log):
    return run(shlex.split(os.environ.get('VVP','vvp'))+[str(binary)]+args,log)

def unit_tests(build):
    rng=random.Random(0x32f0)
    edges=[0,1,2,3,0x7fffffff,0x80000000,0xfffffffe,0xffffffff]
    pairs=[(a,b) for a in edges for b in edges]+[(rng.getrandbits(32),rng.getrandbits(32)) for _ in range(448)]
    dvec=build/'divider.vec'; mvec=build/'muldiv.vec'
    dlines=[]; mlines=[]
    for a,b in pairs:
        expected=[u32(a*b),mulh_ss(a,b),mulh_su(a,b),mulh_uu(a,b),divs(a,b),
                  0xffffffff if b==0 else a//b,rems(a,b),a if b==0 else a%b]
        for op,val in enumerate(expected):
            mlines.append(f'{a:08x} {b:08x} {op} {val:08x}\n')
            if op>=4: dlines.append(f'{a:08x} {b:08x} {int(op%2==0)} {int(op>=6)} {val:08x}\n')
    dvec.write_text(''.join(dlines)); mvec.write_text(''.join(mlines))
    for top,vec,sources in [('tb_divider',dvec,['divider.sv']),
                            ('tb_muldiv_unit',mvec,['muldiv_unit.sv']),
                            ('tb_predictor_unit',None,['branch_predictor.sv'])]:
        binary=build/top
        compile_tb(top,binary,rtl=[ROOT/'rtl'/p for p in sources])
        out=simulate(binary,[f'+VECTORS={vec}'] if vec else [],build/f'{top}.log')
        print(out.splitlines()[0])
    mmio_hex=build/'mmio.hex'
    mmio_hex.write_text(''.join(f'{w:08x}\n' for w in assemble((ROOT/'programs/mmio.s').read_text())))
    compile_tb('tb_mmio',build/'tb_mmio')
    out=simulate(build/'tb_mmio',[f'+HEX={mmio_hex}'],build/'tb_mmio.log')
    print(next(line for line in out.splitlines() if line.startswith('MMIO PASS')))
    reset_hex=build/'reset.hex'
    reset_hex.write_text(''.join(f'{w:08x}\n' for w in assemble(
        'li a0,0x12345678\nsw a0,256(zero)\nli a1,7\ndiv a2,a0,a1\nsw a2,260(zero)\nnop\necall')))
    compile_tb('tb_reset',build/'tb_reset')
    out=simulate(build/'tb_reset',[f'+HEX={reset_hex}'],build/'tb_reset.log')
    print(next(line for line in out.splitlines() if line.startswith('RESET PASS')))
    return {'reset':'PASS','mmio':'PASS','divider_vectors' :len(dlines),'muldiv_vectors':len(mlines),'predictor_unit':'PASS'}

def directed():
    cases={p.stem:p.read_text() for p in sorted((ROOT/'programs').glob('*.s')) if p.stem!='mmio'}
    cases.update({
        'ecall_drain':'li a0,42\nli a1,99\nsw a0,256(zero)\nadd a2,a0,a1\necall\nsw a1,260(zero)\n',
        'lane_boundary':'''li a0,0x80ff7f01
sw a0,1024(zero)
lb a1,1024(zero)
lb a2,1025(zero)
lb a3,1026(zero)
lb a4,1027(zero)
lbu a5,1027(zero)
lh a6,1026(zero)
lhu a7,1026(zero)
li t0,-128
li t1,4095
sb t0,0(t1)
lb t2,0(t1)
lbu t3,0(t1)
li t0,0xabcd
li t1,4094
sh t0,0(t1)
lhu t2,0(t1)
lh t3,0(t1)
ecall
''',
        'divider_dependencies':'''li a0,-2147483648
li a1,-1
sw a0,256(zero)
lw a2,256(zero)
div a3,a2,a1
add a4,a3,a3
rem a5,a0,a1
div a6,a0,zero
rem a7,a0,zero
divu t0,a0,zero
remu t1,a0,zero
li t2,7
div t3,a0,t2
rem t4,a0,t2
sw t3,260(zero)
div t3,t3,t2
sw t3,264(zero)
ecall
''',
        'wrong_path_stop':'''li a0,1
beq a0,a0,safe
ecall
sw a0,256(zero)
safe:
beq a0,zero,poison
jal ra,call_target
sw a0,260(zero)
j done
call_target:
addi a1,ra,1
jalr zero,a1,0
poison:
.word 0xffffffff
done:
fence
ecall
''',
        'forwarding_priority':'''li a0,1
addi a0,a0,1
addi a0,a0,1
add a1,a0,a0
sw a1,256(zero)
lw a2,256(zero)
sw a2,260(zero)
lw zero,256(zero)
addi zero,zero,7
li a3,9
nop
nop
add a4,a3,a0
ecall
''',
        'jalr_changed_target':'''li t0,24
li t1,0
again:
jalr ra,t0,1
j done
nop
nop
addi t1,t1,1
li t0,40
j again
nop
addi t1,t1,2
j done
done:
sw t1,256(zero)
ecall
''',
        'illegal_opcode':'li a0,37\n.word 0xffffffff\nsw a0,256(zero)\necall',
        'illegal_op_funct7':'li a0,37\n.word 0x04000033\nsw a0,256(zero)\necall',
        'illegal_load_funct3':'li a0,37\n.word 0x00003083\nsw a0,256(zero)\necall',
        'illegal_shift':'li a0,37\n.word 0x02001093\nsw a0,256(zero)\necall',
        'illegal_csr':'li a0,37\n.word 0xc0002073\nsw a0,256(zero)\necall',
        'misaligned_lh':'li a0,37\nlh a1,1(zero)\nsw a0,256(zero)\necall',
        'misaligned_lw':'li a0,37\nlw a1,2(zero)\nsw a0,256(zero)\necall',
        'misaligned_sh':'li a0,37\nsh a0,257(zero)\nsw a0,260(zero)\necall',
        'misaligned_sw':'li a0,37\nsw a0,258(zero)\nsw a0,264(zero)\necall',
        'misaligned_jump':'li a0,37\njal a1,2\nsw a0,256(zero)\necall',
        'misaligned_taken_branch':'li a0,37\nbeq a0,a0,2\nsw a0,256(zero)\necall',
        'untaken_misaligned_branch':'li a0,37\nbne a0,a0,2\nsw a0,256(zero)\necall',
        'ebreak_drain':'li a0,37\nadd a1,a0,a0\nebreak\nsw a0,256(zero)\necall',
        'uart_once':'li a0,0x10000000\nli a1,65\nsb a1,0(a0)\nli a2,7\ndiv a3,a1,a2\nsb a3,0(a0)\necall',
    })
    return cases

def random_program(seed,length):
    rng=random.Random(seed); out=['# Seeded RV32IM dependency stress', 'li x29,1024']
    edges=[0,1,-1,0x80000000,0x7fffffff,0xffffffff,0x80ff7f01]
    for reg in range(1,29): out.append(f'li x{reg},{rng.choice(edges) if rng.random()<.6 else rng.getrandbits(32)}')
    for offset in range(0,64,4):
        out += [f'li x28,{rng.getrandbits(32)}',f'sw x28,{offset}(x29)']
    r=lambda:f'x{rng.randrange(28)}'
    for i in range(length):
        kind=rng.randrange(9); rd=r(); a=r(); b=r()
        if kind in (0,1,2):
            op=rng.choice(['add','sub','sll','slt','sltu','xor','srl','sra','or','and',
                           'mul','mulh','mulhsu','mulhu','div','divu','rem','remu'])
            out.append(f'{op} {rd},{a},{b}')
        elif kind==3:
            op=rng.choice(['addi','slti','sltiu','xori','ori','andi'])
            out.append(f'{op} {rd},{a},{rng.randrange(-2048,2048)}')
        elif kind==4:
            op=rng.choice(['slli','srli','srai']); out.append(f'{op} {rd},{a},{rng.randrange(32)}')
        elif kind==5:
            op=rng.choice(['lb','lbu','lh','lhu','lw']); align=4 if op=='lw' else 2 if 'h' in op else 1
            offset=rng.randrange(64//align)*align
            out += [f'{op} {rd},{offset}(x29)',f'add {rd},{rd},{b}']
        elif kind==6:
            op=rng.choice(['sb','sh','sw']); align={'sb':1,'sh':2,'sw':4}[op]
            out.append(f'{op} {b},{rng.randrange(64//align)*align}(x29)')
        elif kind==7:
            op=rng.choice(['beq','bne','blt','bge','bltu','bgeu'])
            out += [f'{op} {a},{b},skip_{i}',f'addi {rd},{a},1',f'sw {rd},64(x29)',f'skip_{i}:']
        else:
            # JALR's low target bit must be cleared, and its link can be forwarded.
            out += ['auipc x28,0',f'jalr {rd},x28,13',f'sw {a},68(x29)']
    out += ['fence','ecall','sw x28,72(x29)']
    return '\n'.join(out)+'\n'

KEYS=['pc','instr','rd','wdata','mem_we','mem_addr','mem_wdata','mem_size','stop','fault','cause']
def normalized(ev):
    d=dict(ev)
    if not d['mem_we']: d['mem_addr']=d['mem_wdata']=d['mem_size']=0
    else: d['mem_wdata'] &= (1<<(8*(1<<d['mem_size'])))-1
    return d

def check_case(binary,name,source,outdir,wave=False):
    case=outdir/name; case.mkdir(parents=True,exist_ok=True)
    (case/'program.s').write_text(source)
    image=assemble(source); hexfile=case/'program.hex'
    hexfile.write_text(''.join(f'{w:08x}\n' for w in image))
    if len(image)>4096: raise ValueError('program exceeds regression instruction memory')
    model=CPU(image,mem_bytes=4096); model.run()
    signatures={'demo':{0x100:55,0x104:110,0x108:1,0x10c:165},
                'branch_bench':{0x1c0:820},'dot_product':{0x300:u32(-137)},
                'rv32m_demo':{0x180:126,0x184:0xffffffff,0x188:0xffffffff,0x18c:5,
                              0x190:3,0x194:715827881,0x198:0xffffffff,0x19c:3}}
    for addr,val in signatures.get(name,{}).items():
        if model.load32(addr)!=val: raise AssertionError(f'{name}: reference failed known signature at {addr:#x}')
    args=[f'+HEX={hexfile}',f'+TRACE={case}/rtl.trace',f'+STATE={case}/rtl.state']
    if wave: args += [f'+VCD={case}/wave.vcd']
    output=simulate(binary,args,case/'simulation.log')
    actual=[]
    for line in (case/'rtl.trace').read_text().splitlines():
        v=[int(x,16) for x in line.split()]
        if len(v)!=len(KEYS): raise AssertionError(f'{name}: malformed trace')
        actual.append(dict(zip(KEYS,v)))
    (case/'reference.jsonl').write_text(''.join(json.dumps(e)+'\n' for e in model.trace))
    if len(actual)!=len(model.trace):
        raise AssertionError(f'{name}: event count RTL={len(actual)} model={len(model.trace)}')
    for i,(a,b) in enumerate(zip(actual,model.trace)):
        a,b=normalized(a),normalized(b)
        if a!=b:
            fields={k:(f'{a[k]:x}',f'{b[k]:x}') for k in KEYS if a[k]!=b[k]}
            raise AssertionError(f'{name}: event {i}, PC={b["pc"]:#x}, instruction={b["instr"]:08x}: RTL/model {fields}')
    state=[int(x,16) for x in (case/'rtl.state').read_text().split()]
    if state[:32]!=model.x: raise AssertionError(f'{name}: final registers differ')
    expected=[model.load32(a) for a in range(0,4096,4)]
    if state[32:]!=expected: raise AssertionError(f'{name}: final memory differs')
    match=re.search(r'METRICS (.*)',output)
    if not match: raise AssertionError('missing RTL metrics')
    stats={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',match.group(1))}
    if stats['instret']!=len(model.trace)-1: raise AssertionError('wrong retirement count')
    if bool(stats['fault'])!=model.faulted or stats['cause']!=model.fault_cause:
        raise AssertionError('wrong fault report')
    return {'program':name,'events':len(actual),**stats}

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--seeds',type=int,default=12); ap.add_argument('--length',type=int,default=160)
    ap.add_argument('--seed',type=int,default=42); ap.add_argument('--build',type=Path,default=ROOT/'build/regression')
    ap.add_argument('--configs',nargs='+',choices=CONFIGS,default=list(CONFIGS))
    ap.add_argument('--skip-units',action='store_true'); ap.add_argument('--wave',action='store_true')
    ap.add_argument('--report',type=Path,default=ROOT/'results/regression.json')
    args=ap.parse_args()
    if args.seeds<0 or args.length<0: ap.error('seeds and length must be nonnegative')
    build=args.build.resolve(); build.mkdir(parents=True,exist_ok=True)
    started=time.monotonic(); units={} if args.skip_units else unit_tests(build)
    cases=directed()
    cases.update({f'random_{args.seed+i}':random_program(args.seed+i,args.length) for i in range(args.seeds)})
    records=[]
    for cfg in args.configs:
        it,bp=CONFIGS[cfg]; binary=build/cfg
        compile_tb('tb_regression',binary,{'ITERATIVE_DIV':it,'ENABLE_BP':bp})
        for name,source in cases.items():
            stats=check_case(binary,name,source,build/(cfg+'_cases'),args.wave and name=='divider_dependencies')
            records.append({'configuration':cfg,**stats})
        print(f'{cfg}: PASS {len(cases)} programs / {sum(x["events"] for x in records if x["configuration"]==cfg)} architectural events')
    report={'status':'PASS','generated_utc':datetime.now(timezone.utc).isoformat(),
            'configuration_parameters':{'bp_entries':64,'dmem_bytes':4096,'imem_words':4096,
                                        'clock_period_ns':10,'terminal_markers_count_as_retired':False},
            'status_detail':'All events, final registers and RAM matched; in-bench counters/store/halt checks passed','seed_start':args.seed,'random_seeds':args.seeds,'random_length':args.length,
            'configurations':args.configs,'unit_tests':units,'program_runs':len(records),
            'architectural_events':sum(x['events'] for x in records),'records':records,
            'tools':{'iverilog':run(shlex.split(os.environ.get('IVERILOG','iverilog'))+['-V']).splitlines()[0],
                     'python':sys.version.split()[0]},'elapsed_seconds':round(time.monotonic()-started,2)}
    args.report.parent.mkdir(parents=True,exist_ok=True); args.report.write_text(json.dumps(report,indent=2)+'\n')
    with args.report.with_suffix('.csv').open('w',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(records[0])); writer.writeheader(); writer.writerows(records)
    print(f'PASS: {report["program_runs"]} RTL program runs, {report["architectural_events"]} matched architectural events; {args.report.relative_to(ROOT)}')
if __name__=='__main__':
    try: main()
    except (AssertionError,RuntimeError,subprocess.TimeoutExpired) as e: sys.exit(f'FAIL: {e}')
