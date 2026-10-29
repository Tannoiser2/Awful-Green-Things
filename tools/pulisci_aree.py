import cv2,numpy as np
im=cv2.imread('board.png'); h,s,v=cv2.split(cv2.cvtColor(im,cv2.COLOR_BGR2HSV))
yel=((h>=15)&(h<=40)&(s>60)&(v>120))
dark=(v<95)
wall=(yel|dark).astype(np.uint8)
ws=np.load('wsf2.npy').astype(np.int32)
free=(1-wall).astype(np.uint8); free[:, :870]=0
n,lab,st,_=cv2.connectedComponentsWithStats(free,connectivity=4)
print('comps',n)
out=np.zeros_like(ws)
# majority label per component
flat=lab.ravel(); wl=ws.ravel()
M=np.zeros((n,46),np.int64)
np.add.at(M,(flat,wl),1)
for c in range(1,n):
    row=M[c]; tot=row.sum()
    best=int(np.argmax(row[1:]))+1
    inner=tot-row[0]
    if inner>=0.5*tot and row[best]>=0.8*inner:
        out[lab==c]=best
    else:
        sel=(lab==c)
        out[sel]=ws[sel]
for i in range(1,46):
    m=(out==i).astype(np.uint8)
    m=cv2.morphologyEx(m,cv2.MORPH_CLOSE,np.ones((9,9),np.uint8))
    ff=m.copy(); H,W=ff.shape; mk=np.zeros((H+2,W+2),np.uint8); cv2.floodFill(ff,mk,(0,0),2); m[ff==0]=1
    nn,l2,s2,_=cv2.connectedComponentsWithStats(m)
    if nn<2: print("VUOTA",i); continue
    m=(l2==1+np.argmax(s2[1:,4]))
    out[m&(out==0)]=i
    print(i,int((ws==i).sum()),int(m.sum()),end='; ')
np.save('wsf3.npy',out.astype(np.int16))
