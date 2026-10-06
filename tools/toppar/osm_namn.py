#!/usr/bin/env python3
"""Namn från OpenStreetMap till toppar som saknar namn i Toppar_v2.gpkg (namn som börjar med "Topp 1234 m").
Hämtar natural=peak med namn i Sverige + gränsområdet via Overpass, matchar inom 300 m (och höjd ±25 m om OSM har höjd).
Skriver förslagen till kod/toppar_osm_forslag.csv och – med --spara – in i gpkg-filen (namnkalla = 'OSM').
Kör:  python3 ~/Dokument/Claude/HitochDit/kod/hitochdit/tools/toppar/osm_namn.py [--spara]"""
import json, math, os, re, sqlite3, sys, csv, time, urllib.parse, urllib.request, urllib.error
KOD = os.path.expanduser(os.environ.get('HITOCHDIT_KOD', '~/Dokument/Claude/HitochDit/kod'))
GPKG = os.path.join(KOD, "Toppar_v3.gpkg" if os.path.exists(os.path.join(KOD, "Toppar_v3.gpkg")) else "Toppar_v2.gpkg")
FRAGA = """[out:json][timeout:300];
( node["natural"="peak"]["name"](55.0,10.5,69.2,24.5); node["natural"="peak"]["name:sv"](55.0,10.5,69.2,24.5); );
out tags;"""
SERVRAR = ["https://overpass-api.de/api/interpreter", "https://overpass.private.coffee/api/interpreter",
           "https://maps.mail.ru/osm/tools/overpass/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]

def sweref(lat, lon):
    """WGS84 -> SWEREF 99 TM (Lantmäteriets formler för Gauss-Krüger, GRS80)"""
    a, f = 6378137.0, 1 / 298.257222101; e2 = f * (2 - f); n = f / (2 - f); ah = a / (1 + n) * (1 + n * n / 4 + n ** 4 / 64)
    A = e2; B = (5 * e2 ** 2 - e2 ** 3) / 6; C = (104 * e2 ** 3 - 45 * e2 ** 4) / 120; D = 1237 * e2 ** 4 / 1260
    b1 = n / 2 - 2 * n * n / 3 + 5 * n ** 3 / 16 + 41 * n ** 4 / 180; b2 = 13 * n * n / 48 - 3 * n ** 3 / 5 + 557 * n ** 4 / 1440
    b3 = 61 * n ** 3 / 240 - 103 * n ** 4 / 140; b4 = 49561 * n ** 4 / 161280
    p, l = math.radians(lat), math.radians(lon - 15)
    s = math.sin(p); ps = p - s * math.cos(p) * (A + B * s * s + C * s ** 4 + D * s ** 6)
    xi = math.atan(math.tan(ps) / math.cos(l)); eta = math.atanh(math.cos(ps) * math.sin(l))
    N = 0.9996 * ah * (xi + b1 * math.sin(2 * xi) * math.cosh(2 * eta) + b2 * math.sin(4 * xi) * math.cosh(4 * eta)
                       + b3 * math.sin(6 * xi) * math.cosh(6 * eta) + b4 * math.sin(8 * xi) * math.cosh(8 * eta))
    E = 500000 + 0.9996 * ah * (eta + b1 * math.cos(2 * xi) * math.sinh(2 * eta) + b2 * math.cos(4 * xi) * math.sinh(4 * eta)
                                + b3 * math.cos(6 * xi) * math.sinh(6 * eta) + b4 * math.cos(8 * xi) * math.sinh(8 * eta))
    return E, N

def hamta():
    data = urllib.parse.urlencode({"data": FRAGA.replace('out tags;', 'out body;')}).encode()
    for forsok in range(2):
        for url in SERVRAR:
            print(f"→ Frågar OpenStreetMap via {url.split('/')[2]} …", file=sys.stderr)
            try:
                req = urllib.request.Request(url, data=data, headers={"User-Agent": "hitochdit-laddskript (privat hobbyapp)"})
                with urllib.request.urlopen(req, timeout=400) as r: return json.load(r)["elements"]
            except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
                print(f"  ✗ {e} – provar nästa", file=sys.stderr)
        time.sleep(60)
    sys.exit("Kunde inte hämta från OpenStreetMap just nu.")

def hojd(t):
    m = re.match(r'^\s*(\d+(?:[.,]\d+)?)', t.get('ele', '') or '')
    return float(m.group(1).replace(',', '.')) if m else None

el = hamta()
osm = []
for e in el:
    t = e.get('tags', {}); namn = t.get('name:sv') or t.get('name')
    if namn and 'lat' in e:
        x, y = sweref(e['lat'], e['lon']); osm.append((x, y, namn, hojd(t), e['id']))
print(f"→ {len(osm)} namngivna toppar i OSM", file=sys.stderr)

g = sqlite3.connect(GPKG)
rader = g.execute("select fid, namn, hojd, x, y from toppar where namn like 'Topp % m%'").fetchall()
anvanda = {n for (n,) in g.execute("select namn from toppar where namn not like 'Topp % m%'")}
forslag = []
for fid, namn, h, x, y in rader:
    kand = [(math.dist((x, y), (ox, oy)), on, oh, oid) for ox, oy, on, oh, oid in osm if abs(ox - x) < 400 and abs(oy - y) < 400]
    kand = [k for k in kand if k[0] <= 300 and (k[2] is None or abs(k[2] - h) <= 25)]
    if kand:
        d, on, oh, oid = min(kand)
        forslag.append((fid, h, namn, on, round(d), oh, oid, on in anvanda))
with open(os.path.join(KOD, 'toppar_osm_forslag.csv'), 'w', newline='') as f:
    w = csv.writer(f); w.writerow(['fid', 'hojd', 'nuvarande', 'osm_namn', 'avstand_m', 'osm_hojd', 'osm_id', 'namnet_finns_redan'])
    w.writerows(forslag)
print(f"→ {len(rader)} toppar utan namn, {len(forslag)} fick förslag från OSM ({sum(1 for f in forslag if f[7])} krockar med namn som redan används)")
for f in forslag[:40]: print(f"  {f[1]} m: {f[3]}  ({f[4]} m bort{', OSM ' + str(round(f[5])) + ' m' if f[5] else ''}){'  ⚠ namnet används redan' if f[7] else ''}")
if '--spara' in sys.argv:
    for fid, h, namn, on, d, oh, oid, krock in forslag:
        if not krock: g.execute("update toppar set namn = ?, namnkalla = 'OSM' where fid = ?", (on, fid))
    g.commit(); print(f"✓ Sparat i {os.path.basename(GPKG)} (namn som redan används hoppades över)")
else:
    print("ℹ Bara förslag. Ser de bra ut: kör igen med --spara (eller rätta i QGIS).")
