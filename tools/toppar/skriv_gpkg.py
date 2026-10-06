"""Skriver toppar.csv till en ny GeoPackage (samma struktur som Henriks Toppar.gpkg) utan GDAL: kopierar strukturen och byter rader."""
import sqlite3, csv, os, struct, sys
KOD = os.path.expanduser(os.environ.get('HITOCHDIT_KOD', '~/Dokument/Claude/HitochDit/kod'))
mall = sqlite3.connect('file:' + os.path.join(KOD, 'Toppar.gpkg') + '?mode=ro', uri=True)
ut = os.path.join(KOD, sys.argv[1] if len(sys.argv) > 1 else 'Toppar_v2.gpkg')
if os.path.exists(ut): os.remove(ut)
ny = sqlite3.connect(ut); mall.backup(ny); ny.execute('pragma journal_mode=delete')
# Rumsliga indexets triggers kräver GDAL/SpatiaLite-funktioner – tas bort (QGIS klarar sig utan, kan skapa om det)
for (namn,) in ny.execute("select name from sqlite_master where type='trigger'").fetchall(): ny.execute(f'drop trigger "{namn}"')
for (namn,) in ny.execute("select name from sqlite_master where type='table' and name like 'rtree_%' and name not like '%\\_node' escape '\\' and name not like '%\\_parent' escape '\\' and name not like '%\\_rowid' escape '\\'").fetchall():
    ny.execute(f'drop table "{namn}"')
ny.execute("delete from gpkg_extensions where extension_name = 'gpkg_rtree_index'")
ny.execute('delete from toppar')
kol = [c[1] for c in ny.execute("pragma table_info(toppar)")]
def punkt(x, y): return b'GP' + bytes([0, 1]) + struct.pack('<i', 3006) + struct.pack('<BId2', 1, 1, x, y) if False else b'GP\x00\x01' + struct.pack('<i', 3006) + struct.pack('<BIdd', 1, 1, x, y)
n = 0
for r in csv.DictReader(open(os.path.join(KOD, 'toppar.csv'))):
    rad = {'geom': punkt(float(r['x']), float(r['y'])), **{k: r.get(k) for k in kol if k not in ('fid', 'geom')}}
    for k in ('hojd', 'rang', 'lan', 'lanrang', 'x', 'y'):
        if k in rad: rad[k] = int(float(rad[k])) if rad[k] not in (None, '') else None
    ks = [k for k in kol if k in rad]
    ny.execute(f"insert into toppar ({','.join(ks)}) values ({','.join('?' * len(ks))})", [rad[k] for k in ks]); n += 1
x = [r for r in ny.execute('select min(x), min(y), max(x), max(y) from toppar')][0]
ny.execute("update gpkg_contents set min_x=?, min_y=?, max_x=?, max_y=?, last_change=strftime('%Y-%m-%dT%H:%M:%fZ','now') where table_name='toppar'", x)
ny.commit(); print('skrev', n, 'toppar till', ut)
