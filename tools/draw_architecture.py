#!/usr/bin/env python3
"""Generate precise, editable architecture SVGs without image generation."""
from pathlib import Path
from html import escape
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/assets'; OUT.mkdir(parents=True,exist_ok=True)
NAVY='#172c45'; INK='#33475e'; MUTED='#64758b'; TEAL='#008f83'; BLUE='#3568bf'; AMBER='#bf7217'

def canvas(w,h):
    return [f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">',
            '<defs><marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="context-stroke"/></marker></defs>',
            f'<rect width="{w}" height="{h}" fill="#f6f8fc"/>']

def text(s,x,y,t,size=22,color=INK,weight='normal',anchor='start'):
    s.append(f'<text x="{x}" y="{y}" font-family="DejaVu Sans,Arial,sans-serif" font-size="{size}" font-weight="{weight}" text-anchor="{anchor}" fill="{color}">{escape(str(t))}</text>')

def rect(s,x,y,w,h,fill='white',stroke='#d9e1ec',radius=16):
    s.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" fill="{fill}" stroke="{stroke}" stroke-width="2"/>')

def path(s,d,color=INK,dash=False,arrow=True):
    s.append(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="3"'+(' stroke-dasharray="8 6"' if dash else '')+(' marker-end="url(#arrow)"' if arrow else '')+'/>')

def finish(s,name):
    (OUT/name).write_text('\n'.join(s+['</svg>']))

s=canvas(1600,860)
text(s,60,66,'RV32FORGE',40,NAVY,'bold')
text(s,60,105,'Five-stage RV32IM core · speculation, back-pressure, and ordered retirement',22,MUTED)
rect(s,60,140,245,105,'#eaf1fc','#c4d5ef')
text(s,182,178,'Branch predictor',21,BLUE,'bold','middle')
text(s,182,211,'Tagged BTB + 2-bit BHT',16,BLUE,anchor='middle')
path(s,'M 182 245 L 182 290',BLUE)
path(s,'M 792 290 L 792 248 L 237 248 L 237 290',BLUE)
text(s,485,234,'EX recovery: direction + target',19,BLUE,anchor='middle')
stages=[('IF','Fetch',['PC + next-PC mux','Instruction memory','Prediction metadata']),
        ('ID','Decode',['Register file + bypass','Immediate generation','Encoding guard']),
        ('EX','Execute',['ALU + shared multiplier','Iterative DIV / REM','Forward + resolve branch']),
        ('MEM','Memory',['Aligned word response','Byte / halfword selection','RAM and MMIO stores']),
        ('WB','Retire',['Register writeback','Ordered commit trace','Terminal marker drain'])]
for i,(abbr,title,lines) in enumerate(stages):
    x=60+i*305
    rect(s,x,290,245,240)
    rect(s,x+18,308,54,40,NAVY,NAVY,9); text(s,x+45,336,abbr,20,'white','bold','middle')
    text(s,x+122,383,title,25,NAVY,'bold','middle')
    for j,line in enumerate(lines):text(s,x+122,423+j*32,line,16,INK,anchor='middle')
    if i<4:
        path(s,f'M {x+245} 401 L {x+305} 401')
        text(s,x+275,387,['IF/ID','ID/EX','EX/MEM','MEM/WB'][i],13,MUTED,anchor='middle')
# Bypass paths convey the two required forwarding destinations.
path(s,'M 1402 530 L 1402 575 L 487 575 L 487 530',TEAL)
path(s,'M 830 575 L 830 530',TEAL)
path(s,'M 1097 530 L 1097 556 L 792 556 L 792 530',TEAL)
text(s,580,603,'WB → ID bypass / WB → EX forwarding',17,TEAL,anchor='middle')
text(s,1192,551,'MEM → EX',15,TEAL,anchor='middle')
rect(s,542,640,500,145,'#fff4e5','#ebcc9f')
text(s,792,678,'Divider owns EX until completion',22,AMBER,'bold','middle')
text(s,792,714,'Hold PC, IF/ID, and ID/EX',20,AMBER,anchor='middle')
text(s,792,749,'Inject MEM bubbles; older work drains',18,INK,anchor='middle')
path(s,'M 792 640 L 792 613',AMBER,dash=True)
rect(s,1097,640,428,145,'#e8f5f2','#acd7cf')
text(s,1311,678,'Observable execution',22,TEAL,'bold','middle')
text(s,1311,714,'PC · instruction · register / store effect',17,INK,anchor='middle')
text(s,1311,749,'Cycles · retired · stalls · predictions',17,INK,anchor='middle')
path(s,'M 1402 612 L 1402 640',TEAL)
text(s,60,690,'Memory contract',22,NAVY,'bold')
text(s,60,725,'Separate instruction and data ports',18,INK)
text(s,60,758,'Combinational reads, synchronous stores',18,INK)
text(s,60,823,'Default: iterative divider + dynamic prediction. Parameters expose matched comparison configurations.',18,MUTED)
finish(s,'architecture.svg')

s=canvas(1400,690)
text(s,55,65,'ONE QUOTIENT BIT PER CYCLE',34,NAVY,'bold')
text(s,55,104,'A restoring divider shared by signed / unsigned DIV and REM',22,MUTED)
boxes=[(55,'Latch request',['a, b, signed, remainder','Capture operands once']),
       (390,'Magnitude state',['Q: 32 bits, R: 33 bits','D: divisor, count: 6 bits']),
       (725,'Restoring step',['Shift R with Q[31]','Compare R′ ≥ D; subtract']),
       (1060,'Finish',['Select quotient / remainder','Restore result sign'])]
for i,(x,title,lines) in enumerate(boxes):
    rect(s,x,185,285,200)
    text(s,x+142,230,title,23,NAVY,'bold','middle')
    for j,line in enumerate(lines):text(s,x+142,282+j*38,line,16,INK,anchor='middle')
    if i<3:path(s,f'M {x+285} 278 L {x+335} 278',TEAL)
path(s,'M 867 385 L 867 430 L 532 430 L 532 385',AMBER)
text(s,700,466,'32 iterations: Q ← next quotient, R ← next remainder',19,AMBER,anchor='middle')
rect(s,55,515,625,110,'#eaf1fc','#c4d5ef')
text(s,80,552,'Early completion',21,BLUE,'bold')
text(s,80,588,'b = 0 or signed MIN / −1 → defined result, no iteration',18,INK)
rect(s,720,515,625,110,'#e8f5f2','#acd7cf')
text(s,745,552,'Handshake',21,TEAL,'bold')
text(s,745,588,'start while idle → busy → one-cycle done + result',18,INK)
finish(s,'divider.svg')

s=canvas(1400,675)
text(s,55,65,'PIPELINE OWNERSHIP AND DRAIN',34,NAVY,'bold')
text(s,55,105,'Stage actions at the next rising clock edge',22,MUTED)
headers=['Event (priority order)','PC / IF/ID','ID/EX','EX/MEM','MEM/WB']
widths=[430,230,230,230,230]; xs=[25,455,685,915,1145]
for x,w,h in zip(xs,widths,headers):
    rect(s,x,155,w,62,NAVY,NAVY,0); text(s,x+w/2,194,h,21,'white','bold','middle')
rows=[('Stop detected in EX','Hold / kill','Kill younger','Terminal marker','Older work advances'),
      ('Branch recovery','Redirect / kill','Kill younger','Branch advances','Older work advances'),
      ('DIV / REM waiting','Hold','Hold owner','Bubble','Older work advances'),
      ('Load-use dependency','Hold','Bubble','Load advances','Older work advances'),
      ('Normal execution','Advance','Advance','Advance','Advance')]
for i,row in enumerate(rows):
    y=217+i*72
    for j,(x,w,t) in enumerate(zip(xs,widths,row)):
        rect(s,x,y,w,72,'white' if i%2==0 else '#edf2f8','#d9e1ec',0)
        text(s,x+(18 if j==0 else w/2),y+44,t,18,INK,'bold' if j==0 else 'normal','start' if j==0 else 'middle')
text(s,55,624,'A terminal marker raises halted in WB. Older effects finish; younger effects never reach memory.',20,TEAL)
finish(s,'pipeline_control.svg')
print('Wrote architecture.svg, divider.svg, pipeline_control.svg')
