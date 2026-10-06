"""Hittar toppar bland Topo100:s höjdpunkter med hjälp av höjdkurvorna (10 m).
topp      = punkten ligger inne i en sluten höjdkurva (närmast under punkten) som inte innehåller något högre
prim30    = samma test på kurvan >= 30 m under punkten -> primärfaktor > 30 m (None = kurvan gick inte att sluta, t.ex. mot sjö/hav)
Skriver resultat.csv. Kan avbrytas och fortsätta (hoppar över punkter som redan finns i filen)."""
import sqlite3, sys, os, csv, math, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); from gpkg import wkb
# Mappen med geodatafilerna (utanför repot)
KOD = os.path.expanduser(os.environ.get('HITOCHDIT_KOD', '~/Dokument/Claude/HitochDit/kod'))
DB = os.path.join(KOD, 'hojd_sverige/hojd_sverige_topo100.gpkg')
c = sqlite3.connect('file:' + DB + '?mode=ro', uri=True)

def linjer(x0, y0, x1, y1, niva=None, over=None):
    sql = """select cast(l.hojdvarde as int), l.objekttyp, l.stodkurva, l.geom from hojdlinje l join rtree_hojdlinje_geom r on r.id = l.fid
             where r.maxx >= ? and r.minx <= ? and r.maxy >= ? and r.miny <= ?"""
    p = [x0, x1, y0, y1]
    if niva is not None: sql += " and l.hojdvarde = ? and l.objekttyp = 'Höjdkurva10'"; p.append(str(niva))
    if over is not None: sql += " and cast(l.hojdvarde as int) > ?"; p.append(over)
    return c.execute(sql, p).fetchall()

def kedjor(delar):
    """Fogar ihop linjebitar med gemensamma ändpunkter. Returnerar (slutna ringar, antal öppna)."""
    k = lambda p: (round(p[0], 1), round(p[1], 1))
    rest = [list(d) for d in delar if len(d) >= 2]
    ringar = [d for d in rest if k(d[0]) == k(d[-1])]
    oppna = [d for d in rest if k(d[0]) != k(d[-1])]
    andar = {}
    for i, d in enumerate(oppna):
        andar.setdefault(k(d[0]), []).append(i); andar.setdefault(k(d[-1]), []).append(i)
    anv = [False] * len(oppna); n_oppna = 0; ofullst = []
    for i in range(len(oppna)):
        if anv[i]: continue
        anv[i] = True; kedja = list(oppna[i])
        for riktning in (0, 1):
            while True:
                slut = k(kedja[-1])
                nasta = [j for j in andar.get(slut, []) if not anv[j]]
                if not nasta: break
                j = nasta[0]; anv[j] = True; d = oppna[j]
                kedja += (d[1:] if k(d[0]) == slut else d[::-1][1:])
                if k(kedja[-1]) == k(kedja[0]): break
            if k(kedja[-1]) == k(kedja[0]): break
            kedja.reverse()
        if k(kedja[-1]) == k(kedja[0]): ringar.append(kedja)
        else: n_oppna += 1; ofullst.append(kedja)
    kedjor.ofullstandiga = ofullst
    return ringar, n_oppna

def inne(p, ring):
    x, y = p; ut = False; n = len(ring)
    for i in range(n - 1):
        x1, y1 = ring[i]; x2, y2 = ring[i + 1]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1: ut = not ut
    return ut

def bbox(r):
    xs = [p[0] for p in r]; ys = [p[1] for p in r]; return min(xs), min(ys), max(xs), max(ys)

def ring_runt(p, niva, max_r=25000):
    """Minsta slutna höjdkurva på nivån som omsluter p. None om den inte går att sluta inom max_r.
    Kurvor som slutar vid riksgränsen (Topo100 täcker bara Sverige) stängs med en rak linje mellan ändpunkterna."""
    r = 1500
    while r <= max_r:
        rader = linjer(p[0] - r, p[1] - r, p[0] + r, p[1] + r, niva=niva)
        delar = [l for *_, g in rader for l in wkb(g)[1]]
        ringar, n_oppna = kedjor(delar)
        kand = [ri for ri in ringar if inne(p, ri)]
        if kand:
            return min(kand, key=lambda ri: (bbox(ri)[2] - bbox(ri)[0]) * (bbox(ri)[3] - bbox(ri)[1]))
        if n_oppna == 0 and r > 1500: return 'ingen'   # inga öppna bitar kvar – punkten ligger inte innanför någon kurva på nivån
        # Öppna kedjor vars båda ändar ligger långt från sökrutans kant = slutar vid gränsen (eller glaciär/vatten) -> stäng med rak linje
        x0, y0, x1, y1 = p[0] - r, p[1] - r, p[0] + r, p[1] + r
        kant = lambda q: min(q[0] - x0, x1 - q[0], q[1] - y0, y1 - q[1]) < 300
        stangda = [kd + [kd[0]] for kd in kedjor.ofullstandiga if not kant(kd[0]) and not kant(kd[-1])]
        kand = [ri for ri in stangda if inne(p, ri)]
        if kand:
            return min(kand, key=lambda ri: (bbox(ri)[2] - bbox(ri)[0]) * (bbox(ri)[3] - bbox(ri)[1]))
        # Alla öppna kedjor slutar inne i rutan (gränsen/glapp) och ingen av dem omsluter punkten – en större ruta ändrar inget
        if r > 1500 and all(not kant(kd[0]) and not kant(kd[-1]) for kd in kedjor.ofullstandiga): return 'ingen'
        r *= 2.5
    return None

def hogre_inne(ring, h, punkter):
    x0, y0, x1, y1 = bbox(ring)
    for _, _, _, g in linjer(x0, y0, x1, y1, over=h):
        for l in wkb(g)[1]:
            if any(inne(q, ring) for q in l[::max(1, len(l) // 8)]): return True
    return any(q[2] > h and x0 <= q[0] <= x1 and y0 <= q[1] <= y1 and inne(q[:2], ring) for q in punkter)

def test(p, h, punkter, upp, djup=60):
    """True/False/None (None = kunde inte avgöras). Letar nedåt från startnivån tills en sluten kurva omsluter punkten
    (Topo100 har 20 m mellan huvudkurvorna och generaliserade kurvor nära topparna)."""
    start = math.ceil(h / 10) * 10 - 10 if upp == 0 else math.floor((h - upp) / 10) * 10
    for niva in range(start, start - djup - 1, -10):
        ring = ring_runt(p, niva)
        if ring is None: return None
        if ring == 'ingen': continue
        return not hogre_inne(ring, h, punkter)
    return False

def lan_polygoner():
    lg = sqlite3.connect('file:' + os.path.join(KOD, 'kommun-lan-rike_aktuell/kommun-lan-rike_aktuell.gpkg') + '?mode=ro', uri=True)
    ut = []
    for kod, namn, g in lg.execute("select lanskod, beslutatnamn, geometri from lan"):
        for poly in wkb(g)[1]:
            ut.append((kod, namn, bbox(poly[0]), poly))
    return ut

def vilket_lan(p, lanpoly):
    for kod, namn, (x0, y0, x1, y1), poly in lanpoly:
        if x0 <= p[0] <= x1 and y0 <= p[1] <= y1 and inne(p, poly[0]) and not any(inne(p, h) for h in poly[1:]):
            return kod, namn
    return '', ''

if __name__ == '__main__':
    # Testar punkter från högsta och nedåt tills det finns minst ANTAL toppar i landet och PER_LAN i varje län (med marginal för dubbletter)
    ANTAL, PER_LAN = 340, 8
    ut = os.path.join(KOD, 'toppar_resultat.csv')
    klara = {}
    if os.path.exists(ut):
        with open(ut) as f: klara = {r['fid']: r for r in csv.DictReader(f)}
    lanpoly = lan_polygoner()
    punkter = []
    for fid, h, typ, g in c.execute("select fid, cast(hojdvarde as int), objekttyp, geom from hojdpunkt"):
        x, y = wkb(g)[1]; punkter.append((x, y, h, typ, fid))
    punkter.sort(key=lambda q: -q[2])
    ok = lambda r: r['topp'] == 'True' and r['prim30'] == 'True'
    antal = sum(1 for r in klara.values() if ok(r)); per_lan = {}
    for r in klara.values():
        if ok(r): per_lan[r['lan']] = per_lan.get(r['lan'], 0) + 1
    ny = not os.path.exists(ut)
    with open(ut, 'a', newline='') as f:
        w = csv.writer(f)
        if ny: w.writerow(['fid', 'hojd', 'typ', 'x', 'y', 'lan', 'lannamn', 'topp', 'prim30'])
        slut = time.time() + float(os.environ.get('SEKUNDER', '1e9'))
        for i, (x, y, h, typ, fid) in enumerate(punkter):
            if time.time() > slut: print('PAUS', antal, flush=True); break
            if str(fid) in klara: continue
            kod, namn = vilket_lan((x, y), lanpoly)
            if antal >= ANTAL and (not kod or per_lan.get(kod, 0) >= PER_LAN): continue
            topp = test((x, y), h, punkter, 0)
            prim = test((x, y), h, punkter, 30, djup=20) if topp else ''
            w.writerow([fid, h, typ, round(x), round(y), kod, namn, topp, prim]); f.flush()
            if topp is True and prim is True:
                antal += 1; per_lan[kod] = per_lan.get(kod, 0) + 1
            if i % 200 == 0: print(time.strftime('%H:%M'), i, h, 'toppar', antal, 'län klara', sum(1 for v in per_lan.values() if v >= PER_LAN), flush=True)
        else:
            print('KLART', antal, sorted(per_lan.items()), flush=True)
