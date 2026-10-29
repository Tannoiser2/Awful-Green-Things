import numpy as np, json, cv2, re
ws=np.load('wsf2.npy').astype(int)
src=open('/home/claude/awful-green-things/tools/genera_aree.py').read()
IDS=eval(re.search(r'IDS = (\[.*?\])',src,re.S).group(1))
PAIRS=re.search(r'PAIRS = """(.*?)"""',src,re.S).group(1).replace('\n','')
N=len(IDS); idx={k:i+1 for i,k in enumerate(IDS)}
adjm=np.zeros((N+2,N+2),bool)
for p in PAIRS.split('|'):
    a,b=p.split(); adjm[idx[a],idx[b]]=adjm[idx[b],idx[a]]=True
OPEN=eval(re.search(r'OPEN = (\[.*?\])',src,re.S).group(1))
openm=np.zeros((N+2,N+2),bool)
for a,b in OPEN: openm[idx[a],idx[b]]=openm[idx[b],idx[a]]=True
cor=np.array([False]+[k.startswith('c_') for k in IDS]+[False])
S=2; w2=ws[::S,::S]; H,W=w2.shape
rng=np.random.default_rng(1)
angs=np.linspace(0,2*np.pi,240,endpoint=False)
los={i:set() for i in range(1,N+1)}
def cast(A,Y0,X0,start):
    n=len(Y0)
    Y0=np.repeat(Y0,len(angs)); X0=np.repeat(X0,len(angs))
    DY=np.tile(np.sin(angs),n); DX=np.tile(np.cos(angs),n)
    cur=np.full(len(Y0),start); gap=np.zeros(len(Y0),int); alive=np.ones(len(Y0),bool)
    for t in range(1,1400):
        y=(Y0+DY*t).astype(int); x=(X0+DX*t).astype(int)
        alive&=(y>=0)&(x>=0)&(y<H)&(x<W)
        if not alive.any(): break
        L=np.zeros(len(Y0),int); L[alive]=w2[y[alive],x[alive]]
        z=alive&(L==0); gap[z]+=1; alive&=~(z&(gap>6))
        nz=alive&(L!=0); gap[nz]=0
        ch=nz&(L!=cur)
        allow=ch&openm[cur,L]
        for l in np.unique(L[allow]): los[A].add(int(l))
        cur[allow]=L[allow]
        alive&=~(ch&~allow)
k5=np.ones((7,7),np.uint8)
for A in range(1,N+1):
    if cor[A]:
        ys,xs=np.where(w2==A); sel=rng.choice(len(ys),min(150,len(ys)),replace=False)
        cast(A,ys[sel]+.5,xs[sel]+.5,A)
    mA=cv2.dilate((w2==A).astype(np.uint8),k5)>0
    for B in range(1,N+1):
        if adjm[A,B] and cor[B]:
            ys,xs=np.where(mA&(w2==B))
            if len(ys)==0: print('nohatch',IDS[A-1],IDS[B-1]); continue
            sel=rng.choice(len(ys),min(60,len(ys)),replace=False)
            cast(A,ys[sel]+.5,xs[sel]+.5,B)
out={IDS[i-1]:sorted(IDS[j-1] for j in los[i] if j!=i) for i in los}
json.dump(out,open('los.json','w'),indent=0)
for k,v in out.items(): print(k,':',' '.join(v))
