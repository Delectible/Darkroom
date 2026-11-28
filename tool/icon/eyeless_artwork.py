"""Paints the X eyes out of the rabbit logos baked into the stock artwork
(the rendered film canisters and cameras in assets/artwork), for people who
picked any icon but the original (lib/core/brand/app_look.dart):

    python3 tool/icon/eyeless_artwork.py    (needs Pillow + numpy)

writes assets/artwork/eyeless/<name>.webp for every picture whose logo
shows its eyes. Finds the logo near its known spot, then fills each eye
with the head's own colour and grain, feathered. Re-run it whenever the
artwork is re-rendered (and add new pictures with a visible logo to P).
Logos too small to show eyes (vision70, minidv04 behind its screen) are
left as they are."""
import os
import sys
import numpy as np
from collections import deque
from PIL import Image, ImageDraw
P={'cinestill800t':(280,233),'dslr08':(296,277),'ektar100':(280,229),'gold200':(280,233),'hp5plus400':(280,233),
'polaroid600':(283,371),'portra400':(280,229),'super8':(543,509),'superia400':(420,527),'velvia50':(280,229),'webcam05':(256,391)}
# Logos too small or turned for the finder: eye centres, radii, and where
# their own clean head is (offset to clone from), by hand.
EYES={'webcam05':([(254.3,395.8),(259.8,396.8)],(2.4,2.2),(1,4)),
      'superia400':([(418.5,526.0),(421.5,526.0)],(1.4,1.3),(0,3))}
R=30
def bbox(a,n,cx,cy,thr=0.55):

    w=a[cy-R:cy+R, cx-R:cx+R, :3]
    border=np.concatenate([w[0],w[-1],w[:,0],w[:,-1]]); bg=np.median(border,0)
    d=np.linalg.norm(w-bg,axis=-1); gc=np.median(w[d>=np.percentile(d,93)],0); m=d>np.linalg.norm(gc-bg)*thr
    ys,xs=np.nonzero(m); k=np.argmin((ys-R)**2+(xs-R+4)**2); seen=np.zeros_like(m); q=deque([(ys[k],xs[k])]); seen[ys[k],xs[k]]=1
    while q:
        y,x=q.popleft()
        for dy,dx in((1,0),(-1,0),(0,1),(0,-1)):
            Y,X=y+dy,x+dx
            if 0<=Y<2*R and 0<=X<2*R and m[Y,X] and not seen[Y,X]: seen[Y,X]=1; q.append((Y,X))
    ys,xs=np.nonzero(seen)
    return (cx-R+xs.min(), cy-R+ys.min(), cx-R+xs.max()+1, cy-R+ys.max()+1)
def patch(a,b):
    x0,y0,x1,y1=b; W=x1-x0; H=y1-y0
    eyes=[(x0+fx*W+0.5, y0+0.665*H) for fx in (0.267,0.533)]
    return stamp(a,eyes,(0.14*W,0.125*H),(0,int(round(24/129*H))))
def stamp(a,eyes,radii,off=None):
    """Fills each eye with the head's own colour (sampled round it) and a
    matching film grain, feathered into the edge."""
    yy,xx=np.mgrid[0:a.shape[0],0:a.shape[1]].astype(np.float32)
    rx,ry=radii
    cx=sum(e[0] for e in eyes)/2; cy=sum(e[1] for e in eyes)/2
    # the head round the eyes: the pixels most unlike the far surroundings
    near=np.hypot((xx-cx)/(rx*3.2),(yy-cy)/(ry*3.0))<1
    ring=(np.hypot((xx-cx)/(rx*7),(yy-cy)/(ry*6))<1)&~(np.hypot((xx-cx)/(rx*5),(yy-cy)/(ry*4.5))<1)
    bg=np.median(a[ring][:,:3],0)
    eyezone=np.zeros_like(near)
    for ex,ey in eyes: eyezone|=np.hypot((xx-ex)/rx,(yy-ey)/ry)<1.5
    cand=a[near&~eyezone][:,:3]; dist=np.linalg.norm(cand-bg,axis=1)
    head=cand[dist>=np.percentile(dist,60)]
    col=np.median(head,0); grain=float(np.std(head.mean(1)))*0.8
    rng=np.random.default_rng(7)
    noise=rng.normal(0,grain,a.shape[:2])[...,None]
    for ex,ey in eyes:
        r=np.hypot((xx-ex)/rx,(yy-ey)/ry); t=np.clip((1.35-r)/0.35,0,1)[...,None]
        a[...,:3]=a[...,:3]*(1-t)+(col+noise)*t
    return a
def run(src_dir,dst_dir,debug=None):
    dbg=[]
    for n,(cx,cy) in P.items():
        im=Image.open(f'{src_dir}/{n}.webp'); mode=im.mode; a=np.asarray(im.convert('RGBA')).astype(np.float32)
        if n in EYES: b=None; a=stamp(a,*EYES[n])
        else: b=bbox(a,n,cx,cy); a=patch(a,b)
        out=Image.fromarray(np.clip(a,0,255).astype(np.uint8),'RGBA')
        if mode!='RGBA': out=out.convert(mode)
        out.save(f'{dst_dir}/{n}.webp',quality=92,method=6); dbg.append((n,b))
    return dbg
if __name__=='__main__':
    root=os.path.abspath(os.path.join(os.path.dirname(__file__),'..','..'))
    src=os.path.join(root,'assets','artwork'); dst=os.path.join(src,'eyeless')
    os.makedirs(dst,exist_ok=True)
    for n,b in run(src,dst): print(n,b)
