import struct, sqlite3
def wkb(b):
    """GPKG-geometri -> ('Point',(x,y)) | ('Lines',[[(x,y),...],...]) | ('Polys',[[ring,...],...])"""
    flags=b[3]; env=(flags>>1)&7; off=8+[0,32,48,48,64][env]
    return _wkb(b,off)[0]
def _wkb(b,o):
    bo='<' if b[o]==1 else '>'; t=struct.unpack_from(bo+'I',b,o+1)[0]%1000; o+=5
    if t==1:
        x,y=struct.unpack_from(bo+'2d',b,o); return ('Point',(x,y)),o+16
    if t==2:
        n=struct.unpack_from(bo+'I',b,o)[0]; o+=4
        pts=list(zip(*[iter(struct.unpack_from(bo+'%dd'%(2*n),b,o))]*2)); return ('Lines',[pts]),o+16*n
    if t==3:
        nr=struct.unpack_from(bo+'I',b,o)[0]; o+=4; rings=[]
        for _ in range(nr):
            n=struct.unpack_from(bo+'I',b,o)[0]; o+=4
            rings.append(list(zip(*[iter(struct.unpack_from(bo+'%dd'%(2*n),b,o))]*2))); o+=16*n
        return ('Polys',[rings]),o
    if t in (4,5,6):
        n=struct.unpack_from(bo+'I',b,o)[0]; o+=4; parts=[]
        for _ in range(n):
            g,o=_wkb(b,o); parts+= g[1] if g[0]!='Point' else [g[1]]
        return (('Points','Lines','Polys')[t-4],parts),o
    raise ValueError(t)
