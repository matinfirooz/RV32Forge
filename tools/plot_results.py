#!/usr/bin/env python3
"""Publication-style SVG plots sourced only from recorded RTL/synthesis results."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
COLORS={'iterative_dynamic':'#008f83','iterative_static':'#d79b39','combinational_dynamic':'#6473aa'}

def style(plt):
    plt.rcParams.update({'font.family':'DejaVu Sans','font.size':11,'axes.spines.top':False,
        'axes.spines.right':False,'axes.labelcolor':'#33475e','text.color':'#172c45',
        'xtick.color':'#33475e','ytick.color':'#33475e','svg.fonttype':'none',
        'figure.facecolor':'white','axes.axisbelow':True})

def waveform(plt,path,out):
    if not path.exists(): return
    wanted=['div_start','div_busy','div_done','div_wait','dmem_we','commit_valid','pc']
    ids={}; scopes=[]; rows={}; time=0; body=False
    for line in path.read_text().splitlines():
        if not body:
            t=line.split()
            if not t: continue
            if t[0]=='$scope':scopes.append(t[2])
            elif t[0]=='$upscope':scopes.pop()
            elif t[0]=='$var' and scopes==['tb_regression','dut','u_core'] and t[4] in wanted:
                ids[t[3]]=t[4]; rows[t[4]]=[]
            elif t[0]=='$enddefinitions':body=True
        elif line.startswith('#'): time=int(line[1:])
        elif line.startswith('b'):
            value,code=line[1:].split()
            if code in ids and not any(c in value.lower() for c in 'xz'):
                rows[ids[code]].append((time,int(value,2)))
        elif line and line[0] in '01' and line[1:] in ids:
            rows[ids[line[1:]]].append((time,int(line[0])))
    busy=rows['div_busy']; start=next(t for t,v in busy if v)
    end=next(t for t,v in busy if t>start and not v)
    lo=max(0,start-50000); hi=end+50000
    fig,axes=plt.subplots(7,1,figsize=(12,6.7),sharex=True,layout='constrained',gridspec_kw={'hspace':.05})
    for ax,key in zip(axes,wanted):
        samples=rows[key]; prev=0
        for t,v in samples:
            if t<=lo:prev=v
        selected=[(lo,prev)]+[(t,v) for t,v in samples if lo<t<hi]
        selected.append((hi,selected[-1][1]))
        ax.step([(t-lo)/10000 for t,v in selected],[v for t,v in selected],where='post',color='#008f83',linewidth=1.8)
        ax.axvspan((start-lo)/10000,(end-lo)/10000,color='#d79b39',alpha=.14)
        ax.set_ylabel(key,rotation=0,ha='right',va='center',labelpad=13)
        if key!='pc': ax.set_ylim(-.15,1.3); ax.set_yticks([0,1]); ax.set_yticklabels([])
        else:ax.set_yticks(sorted(set(v for t,v in selected)));ax.tick_params(axis='y',labelsize=8)
        ax.grid(axis='x',color='#e2e7ef',linewidth=.7)
    axes[0].set_title('Captured RTL waveform: EX holds a divide while older instructions drain',loc='left',pad=18,fontweight='bold')
    axes[-1].set_xlabel('Testbench cycles in this window (10 ns clock used for functional simulation)')
    fig.savefig(out/'execution.svg',bbox_inches='tight');plt.close(fig)

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--regression',type=Path,default=ROOT/'results/regression.json')
    ap.add_argument('--synthesis',type=Path,default=ROOT/'results/synthesis.json')
    args=ap.parse_args()
    try: import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
    except ImportError: raise SystemExit('Install optional plotting dependencies: python -m pip install -r requirements-viz.txt')
    style(plt); out=ROOT/'docs/assets';out.mkdir(parents=True,exist_ok=True)
    raw=json.loads(args.regression.read_text()); records=raw['records']
    lookup={(r['configuration'],r['program']):r for r in records}
    fig,axes=plt.subplots(1,2,figsize=(12,4.5),layout='constrained')
    groups=[(['branch_bench','dot_product'],['Branch loop','INT8 dot product'],
             ['iterative_dynamic','iterative_static'],'Branch prediction'),
            (['rv32m_demo','div_bench'],['RV32M demo','Dependent divides'],
             ['iterative_dynamic','combinational_dynamic'],'Divider cycle cost')]
    labels={'iterative_dynamic':'Iterative + dynamic','iterative_static':'Iterative + static','combinational_dynamic':'Combinational + dynamic'}
    for ax,(programs,ticks,configs,title) in zip(axes,groups):
        for i,cfg in enumerate(configs):
            x=[j+(i-.5)*.34 for j in range(len(programs))]
            vals=[lookup[(cfg,p)]['cycles'] for p in programs]
            bars=ax.bar(x,vals,width=.31,label=labels[cfg],color=COLORS[cfg])
            ax.bar_label(bars,padding=4,fontsize=10)
        ax.set_xticks(range(len(programs)),ticks);ax.set_ylabel('Cycles to drained halt');ax.set_title(title,loc='left',fontweight='bold')
        ax.set_ylim(0,ax.get_ylim()[1]*1.18); ax.grid(axis='y',alpha=.22);ax.legend(frameon=False,loc='upper left',fontsize=9)
    fig.savefig(out/'benchmark_cycles.svg',bbox_inches='tight');plt.close(fig)
    # Counts rather than a broad predictor-accuracy claim from one small workload.
    fig,ax=plt.subplots(figsize=(6.2,3.6),layout='constrained')
    configs=['iterative_static','iterative_dynamic']; vals=[lookup[(c,'branch_bench')]['mispredicts'] for c in configs]
    bars=ax.barh(['Static not-taken','Dynamic two-bit'],vals,color=[COLORS[c] for c in configs],height=.5)
    ax.bar_label(bars,padding=5);ax.set_xlim(0,44);ax.set_xlabel('Mispredicted control transfers (40 total)')
    ax.set_title('Branch-loop benchmark',loc='left',fontweight='bold');ax.grid(axis='x',alpha=.22)
    fig.savefig(out/'predictor.svg',bbox_inches='tight');plt.close(fig)
    if args.synthesis.exists():
        synth=json.loads(args.synthesis.read_text())
        fig,ax=plt.subplots(figsize=(6.2,3.8),layout='constrained')
        bars=ax.bar(['Iterative DIV / REM','Combinational DIV / REM'],
                    [r['generic_cells'] for r in synth['records']],color=['#008f83','#6473aa'],width=.54)
        ax.bar_label(bars,padding=5,fmt='%.0f');ax.set_ylabel('Yosys generic cells');ax.set_ylim(0,65000)
        ax.set_title(f'Matched core synthesis · {synth["bp_entries"]}-entry predictor',loc='left',fontweight='bold')
        ax.grid(axis='y',alpha=.22)
        fig.text(.5,-.025,'Generic mapping; no physical area, frequency, energy, or power estimate.',ha='center',fontsize=9,color='#64758b')
        fig.savefig(out/'synthesis.svg',bbox_inches='tight');plt.close(fig)
    wave=ROOT/'build/regression/iterative_dynamic_cases/divider_dependencies/wave.vcd'
    waveform(plt,wave if wave.exists() else ROOT/'examples/divider.vcd',out)
    print('Wrote measured benchmark, prediction, synthesis, and execution plots')
if __name__=='__main__': main()
