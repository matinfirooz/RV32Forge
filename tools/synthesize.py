#!/usr/bin/env python3
"""Matched generic-cell synthesis; no technology-specific PPA is inferred."""
from __future__ import annotations
import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess
ROOT=Path(__file__).resolve().parents[1]

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--bp-entries',type=int,default=64)
    ap.add_argument('--build',type=Path,default=ROOT/'build/synthesis')
    ap.add_argument('--report',type=Path,default=ROOT/'results/synthesis.json')
    args=ap.parse_args(); build=args.build.resolve(); build.mkdir(parents=True,exist_ok=True)
    def quote(p): return '"'+str(p).replace('\\','\\\\').replace('"','\\"')+'"'
    sources=sorted(p for p in (ROOT/'rtl').glob('*.sv') if p.name!='rv32_soc.sv')
    records=[]
    for name,it in [('iterative_divider',1),('combinational_divider',0)]:
        stats=build/f'{name}.json'; script=build/f'{name}.ys'; log=build/f'{name}.log'
        script.write_text('read_verilog -sv '+' '.join(quote(p) for p in sources)+'\n'+
            f'chparam -set ITERATIVE_DIV {it} -set BP_ENTRIES {args.bp_entries} rv32_core\n'+
            'hierarchy -check -top rv32_core\n'+
            'synth -top rv32_core -flatten\ncheck -assert\n'+
            f'tee -o {stats.name} stat -json\n')
        cmd=shlex.split(os.environ.get('YOSYS','yosys'))+['-Q','-T','-s',str(script)]
        with log.open('w') as f: p=subprocess.run(cmd,cwd=build,stdout=f,stderr=subprocess.STDOUT,timeout=240)
        if p.returncode: raise SystemExit(f'{name} failed; see {log}')
        raw=json.loads(stats.read_text()); module=raw['modules']['\\rv32_core']
        cells=module['num_cells_by_type']
        flop_count=sum(n for k,n in cells.items() if 'DFF' in k.upper())
        row={'configuration':name,'generic_cells':module['num_cells'],
             'flip_flops':flop_count,'cell_types':cells}
        records.append(row); print(f'{name}: {row["generic_cells"]} generic cells, {flop_count} flip-flops')
    version=subprocess.check_output(shlex.split(os.environ.get('YOSYS','yosys'))+['-V'],text=True).strip()
    report={'status':'PASS','tool':version,'top':'rv32_core','bp_entries':args.bp_entries,
            'method':'Yosys synth -flatten; default ABC generic mapping; all core outputs retained',
            'exclusions':'Simulation RAM/MMIO wrapper excluded. No library mapping, STA, placement, routing, area or power claim.',
            'records':records}
    args.report.parent.mkdir(parents=True,exist_ok=True); args.report.write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__': main()
