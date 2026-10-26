import random
import sys
from collections import Counter
from pathlib import Path
r = random.Random(47019)
widths = {1:[8],2:[16],3:[32],4:[16]*4,5:[32]*4,6:[8]*2,7:[16]*2,8:[24,8],9:[11,11,10],10:[8]*4,11:[10,10,10,2],12:[32]*2,13:[32,8,24],14:[32]*3}
decor_formats = {4,5,9,10,11}
rows = {1:8,2:8,6:8,5:2}
records=[]
coverage=Counter()
def package(fmt, reverse, style, decor):
    ws=widths[fmt]
    ns=[(6 if c==0 else 5) if fmt==14 else 512//sum(ws) for c in range(len(ws))]
    strategy=[r.randrange(2) for _ in ws]
    fields=[(0,2),(fmt,4),(decor,1)]+[(s,1) for s in strategy]
    anchors=[r.getrandbits(w) for w in ws]
    channel_deltas=[]
    planes=[]
    for w,n,s in zip(ws,ns,strategy):
        ib=5 if w==32 else 4 if w>=16 else 3
        terminal=(1<<ib)-1
        choices=[(0,0)]+[(ix,w if ix==terminal and w>terminal else ix+1) for ix in range(1,terminal+1) if (ix<terminal and ix+1<=w) or (ix==terminal and w>terminal)]
        maxdw=style
        choices=[p for p in choices if p[1]<=maxdw]
        selected=[r.choice(choices) for _ in range(n//2 if s else 1)]
        fields.append((sum(ix<<(j*ib) for j,(ix,dw) in enumerate(selected)),len(selected)*ib))
        ds=[]
        value=0
        pos=0
        for k in range(n-1):
            dw=selected[k//2 if s else 0][1]
            bits=r.getrandbits(dw)
            signed=bits-(1<<dw) if dw and bits>>(dw-1) else bits
            ds.append(signed)
            value |= bits<<pos
            pos+=dw
        channel_deltas.append((value,pos))
        rw=rows.get(fmt,4)
        vals=[anchors[len(planes)]]
        for k,d in enumerate(ds,1):
            pred=k-1 if fmt==14 or k%rw else k-rw
            vals.append((vals[pred]+d)&((1<<w)-1))
        planes.append(vals)
    fields += list(zip(anchors,ws)) + channel_deltas
    size=(sum(n for v,n in fields)+7)//8
    bits=0
    pos=size*8 if reverse else 0
    for value,n in fields:
        if reverse: pos-=n
        bits |= value<<pos
        if not reverse: pos+=n
    if decor:
        for c in (0,2):
            for k in range(ns[c]):
                ref=planes[1][k] >> (1 if fmt==9 and c==2 else 0)
                planes[c][k]=(planes[c][k]+ref)&((1<<ws[c])-1)
    raw=0
    off=0
    for c,(w,n) in enumerate(zip(ws,ns)):
        for k in range(n):
            pos=(3*k+c)*32 if fmt==14 else k*sum(ws)+off
            raw |= planes[c][k]<<pos
        off+=w
    return size,bits,raw

for mode in range(6,16):
    pattern=sum((0x10203040+mode-6+j)<<(32*j) for j in range(4))
    raw=sum(pattern<<(128*j) for j in range(8))
    records.append((mode,0,raw,0)); coverage[mode]+=1
for _ in range(20):
    raw=r.getrandbits(1024)
    records.append((0,raw,raw,0)); coverage[0]+=1
for fmt in range(1,15):
    for trial in range(60):
        decor=int(fmt in decor_formats and trial%2==1)
        a,ab,ar=package(fmt,False,r.choice([0,2,4,8,16,32]),decor)
        b,bb,br=package(fmt,True,r.choice([0,2,4,8,16,32]),decor)
        total=a+b
        if max(a,b)>68 or total>96: continue
        if total<=32: mode,occupied=1,32
        elif total<=64:
            mode=2 if a<=32 and b<=32 else 3 if a<32 else 4
            occupied=64
        else: mode,occupied=5,96
        packet=ab | (bb<<((occupied-b)*8))
        records.append((mode,packet,ar|(br<<512),0)); coverage[mode]+=1
        if trial%15==0:
            records.append((mode,packet|3,0,1)); coverage['invalid_reserved']+=1
# The document allows a package larger than two sectors. Exercise both
# orientations explicitly instead of relying on the random width choices.
for wide_role in (0, 1):
    while True:
        wide=package(3,bool(wide_role),32,0)
        if 64 < wide[0] <= 68: break
    small=package(3,not bool(wide_role),0,0)
    first,second=(wide,small) if wide_role==0 else (small,wide)
    a,ab,ar=first
    b,bb,br=second
    assert 64 < a+b <= 96
    records.append((5,ab|(bb<<((96-b)*8)),ar|(br<<512),0))
    coverage['wide_pkg'+str(wide_role)]+=1
r.shuffle(records)
Path(sys.argv[1]).write_text(''.join(f'{m} {bits:0256x} {raw:0256x} {err}\n' for m,bits,raw,err in records))
print('Generated',len(records),'units; coverage',dict(coverage))
