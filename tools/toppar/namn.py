"""Väljer toppar (300 högsta + 5 per län) ur resultat.csv och sätter namn från Topo50-textlagret. Skriver toppar.csv."""
import sqlite3, os, sys, csv, math, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); from gpkg import wkb
# Mappen med geodatafilerna (utanför repot)
KOD = os.path.expanduser(os.environ.get('HITOCHDIT_KOD', '~/Dokument/Claude/HitochDit/kod'))
t = sqlite3.connect('file:' + os.path.join(KOD, 'text_sverige/text_sverige.gpkg') + '?mode=ro', uri=True)

GENERISK = re.compile(r'^(nord|syd|väst|öst|stor|mellan|lill|högsta|norra|södra|västra|östra|lilla|stora)?-?toppen$|^topp(en)?$|^(n|s|v|ö)\.? ?topp', re.I)
TOPPLIK = re.compile(r'(tjåkkå|tjåhkkå|čohkka|cohkka|tjåkko|vár+i|vare|vaara|pakte|bákti|kaise|gaise|topp(en)?|fjäll(et)?|berg(et)?|kulle(n)?|klint(en)?|höjd(en)?|åsen|backe(n)?|skuta(n)?|knöle(n)?|hammare(n)?|klumpe(n)?|stöten|vålen|kläppen|pik|nuten|bränna|tind|ryggen|kammen|hög(en)?|kalle(n)?|hed|gáisi|gaisi|bákte|bákti|bakte|riehppe|riehppi|njunni|spetsen|spets|nállu|tjåhke|tjåhkka|čohkku|oaivi|vaarat|nippa|lassi|åsarna|bergen|knopparna|kullarna|hågna|högen|fjällen|liden)$', re.I)
INTE = re.compile(r'(passet|dal(en)?|vagge|vággi|jaure|jávri|jaur|jiekna|glaciär(en)?|jökel(n)?|myr(en)?|mosse(n)?|sjö(n)?|träsk(et)?|bäck(en)?|älv(en)?|vik(en)?|udde(n)?|sund(et)?|fjärd(en)?|gård(en)?|stuga(n)?|stugorna|skar(et)?|sadeln|slätt(en)?|sänkan|kåtan|vallen|leden|vägen|stigen|parken|reservat(et)?|nationalpark(en)?|torp(et)?|bygget|skog(en)?|skoga|kärr(et)?|fly(et)?|flyn|äng(en)?|ängarna|hage(n)?|gärde(t)?|stäkt(et)?|åker|åkern|tegen|kärret|vreten)$|^(sarek|padjelanta|stora sjöfallet|abisko|muddus|vadvetjåkka)$', re.I)

# Samma berg med svenskt och samiskt namn i kartan – deltoppar ska heta lika
SAMMA = {'Giebmegáisi': 'Kebnekaise'}
# Kända toppar (Wikipedia: Sveriges toppar över 2 000 m) där kartans namn är samiska och/eller etiketten står långt bort – låses på höjd
KANDA = {2071: 'Kaskasatjåkka', 2040: 'Kaskasapakte'}

# Topografi 10:s textlager har betydligt fler namn – används i första hand, Topo50 som komplement
t10p = os.path.expanduser(os.environ.get('HITOCHDIT_TOPO10', '~/Dokument/Geodata/LM Topo10/text_sverige.gpkg'))
t10 = sqlite3.connect('file:' + t10p + '?mode=ro', uri=True) if os.path.exists(t10p) else None
storlek10 = lambda th: 2 if th < 14 else 3 if th < 18 else 4 if th < 22 else 5 if th < 26 else 6   # texthöjd -> storleksklass som i Topo50

def namn_nara(x, y, r):
    ut = {}
    if t10:
        for s, th, g in t10.execute("""select coalesce(nullif(p.regtext, ''), p.text), p.thojd, p.geom from textobjekt p join rtree_textobjekt_geom q on q.id = p.fid
                where q.maxx >= ? and q.minx <= ? and q.maxy >= ? and q.miny <= ? and p.detaljtyp in ('TERRTX', 'TERRUTX')""", (x - r, x + r, y - r, y + r)):
            if not s or not s.strip(): continue
            d = math.dist((x, y), wkb(g)[1])
            if d <= r and (s.strip() not in ut or d < ut[s.strip()][0]): ut[s.strip()] = (d, s.strip(), storlek10(th or 0))
    for d, s, stl in namn_nara50(x, y, r):
        if s not in ut: ut[s] = (d, s, stl)
    return sorted(ut.values())

def namn_nara50(x, y, r):
    rader = t.execute("""select p.textstrang, cast(p.textstorleksklass as int), p.geom from textpunkt p join rtree_textpunkt_geom q on q.id = p.fid
        where q.maxx >= ? and q.minx <= ? and q.maxy >= ? and q.miny <= ? and p.textkategori = 'Terrängnamn'""", (x - r, x + r, y - r, y + r)).fetchall()
    ut = []
    for s, stl, g in rader:
        d = math.dist((x, y), wkb(g)[1])
        if d <= r and s and s.strip(): ut.append((d, s.strip(), stl))
    return sorted(ut)

def satt_namn(x, y, h=0):
    """(namn, hur) – hur = avstånd till namnet, 'deltopp' eller 'nära' (inget eget namn hittat)."""
    nara = [n for n in namn_nara(x, y, 2000) if not INTE.search(n[1])]
    # närmast vinner inom 800 m; topplika namn (…tjåkkå, …toppen, …berget) får räknas på dubbla avståndet, upp till 2 km
    nara = [n for n in namn_nara(x, y, 4000) if not INTE.search(n[1])]
    # stora namn (storleksklass >= 4, t.ex. Helagsfjället) står ofta en bit från toppen – får sökas upp till 4 km
    # topplika namn (…berget, …tjåhkkå, …toppen) inom 2 km; andra namn bara om de står alldeles intill (300 m)
    # (i fjällen, över 800 m, är nästan alla terrängnamn bergsnamn – där räcker 800 m för alla namn)
    nara_grans = 800 if h >= 800 else 300
    kand = [n for n in nara if (n[0] <= nara_grans) or ((TOPPLIK.search(n[1]) or GENERISK.search(n[1])) and n[0] <= 2000)]
    if not kand:   # inget namn nära – ta ett stort bergsnamn längre bort
        kand = [n for n in nara if TOPPLIK.search(n[1]) and n[2] >= 4 and n[0] <= 4000]
    if kand:
        d, namn, stl = min(kand, key=lambda n: n[0] * (0.5 if TOPPLIK.search(n[1]) or GENERISK.search(n[1]) else 1))
        if GENERISK.search(namn):
            massiv = [n for n in namn_nara(x, y, 5000) if (TOPPLIK.search(n[1]) or n[2] >= 5) and not re.search(r'topp(en)?$', n[1], re.I)
                      and not INTE.search(n[1]) and n[2] >= 3]
            if massiv:
                m = min(massiv, key=lambda n: n[0] / n[2])
                return f'{SAMMA.get(m[1], m[1])}, {namn}', 'deltopp'
        return namn, f'{round(d)} m'
    granne = [n for n in namn_nara(x, y, 5000) if not INTE.search(n[1]) and not GENERISK.search(n[1])]
    return '', ('nära ' + granne[0][1]) if granne else 'nära –'

R = list(csv.DictReader(open(os.path.join(KOD, 'toppar_resultat.csv'))))
for r in R: r['hojd'] = int(r['hojd'])
# Primärfaktor > 30 m, eller reservregeln (topp + närmaste högre punkt minst 1,5 km bort) där kurvorna inte gick att sluta
sakra = lambda r: (r['topp'] == 'True' and r['prim30'] == 'True') or r.get('reserv') == 'topp+isolerad'
for r in R:
    if r.get('reserv') == 'topp+isolerad': r['topp'], r['prim30'] = 'True', 'okänd'
    elif r.get('reserv') == 'topp': r['topp'] = 'True'
prim = sorted([r for r in R if sakra(r)], key=lambda r: -r['hojd'])
riket = {r['fid']: i + 1 for i, r in enumerate(prim[:300])}
per_lan = {}
for r in sorted(R, key=lambda r: (-r['hojd'])):
    if r['topp'] != 'True' or r['prim30'] == 'False' or not r['lan']: continue
    per_lan.setdefault(r['lan'], [])
    # i första hand primärfaktor > 30 m, i flacka län fylls det på med toppar där den inte gick att avgöra
    per_lan[r['lan']].append(r)
lanrang = {}
for kod, lista in per_lan.items():
    lista.sort(key=lambda r: (not sakra(r), -r['hojd']))
    urval = []
    for r in lista:
        if len(urval) == 5: break
        if any(math.dist((int(r['x']), int(r['y'])), (int(q['x']), int(q['y']))) < 300 for q in urval): continue
        urval.append(r)
    for i, r in enumerate(sorted(urval, key=lambda r: -r['hojd'])): lanrang[r['fid']] = i + 1
valda = sorted([r for r in R if r['fid'] in riket or r['fid'] in lanrang], key=lambda r: -r['hojd'])
h = sqlite3.connect('file:' + os.path.join(KOD, 'hojd_sverige/hojd_sverige_topo100.gpkg') + '?mode=ro', uri=True)
for r in valda: r['oid'] = h.execute('select objektidentitet from hojdpunkt where fid = ?', (int(r['fid']),)).fetchone()[0]
# Namn som rättats för hand i Toppar.gpkg (QGIS) behålls
handnamn = {}
gp = os.path.join(KOD, 'Toppar.gpkg')
if os.path.exists(gp):
    g = sqlite3.connect('file:' + gp + '?mode=ro', uri=True)
    handnamn = {oid: (n, 'handrättat') for oid, n in g.execute("select objektidentitet, namn from toppar") if n and not re.match(r'^Topp \d+ m', n)}
# Namn som satts för hand eller från OSM i Toppar_v2.gpkg låses också
gp2 = os.path.join(KOD, 'Toppar_v2.gpkg')
if os.path.exists(gp2):
    g2 = sqlite3.connect('file:' + gp2 + '?mode=ro', uri=True)
    for oid, n, k in g2.execute("select objektidentitet, namn, namnkalla from toppar where namnkalla in ('handrättat', 'OSM')"):
        if n and not re.match(r'^Topp \d+ m', n): handnamn[oid] = (n, k)
rader = []
for r in valda:
    if r['hojd'] in KANDA and r['lan'] == '25':
        r['namn'], r['hur'] = KANDA[r['hojd']], 'Wikipedia'; continue
    if r['oid'] in handnamn:
        # Topo10 bedöms som mest rätt: ett låst namn ersätts om Topo10-namnet står inom 150 m från toppen och inte redan ingår,
        # eller om Topo10 ger samma deltopp med bergets namn framför (t.ex. Mellantoppen -> Ähpár, Mellantoppen)
        n10, hur10 = satt_namn(int(r['x']), int(r['y']), r['hojd']); n10 = SAMMA.get(n10, n10); laast = handnamn[r['oid']]
        nara10 = hur10.endswith(' m') and float(hur10[:-2]) <= 150 and n10 and n10.lower() not in laast[0].lower()
        deltopp10 = hur10 == 'deltopp' and n10.lower().endswith(laast[0].lower()) and n10 != laast[0]
        r['namn'], r['hur'] = (n10, 'Topo10 (ersatte ' + laast[0] + ')') if nara10 or deltopp10 else laast
        continue
    r['namn'], r['hur'] = satt_namn(int(r['x']), int(r['y']), r['hojd'])
    r['namn'] = SAMMA.get(r['namn'], r['namn'])
    r['avst'] = float(r['hur'][:-2]) if r['hur'].endswith(' m') else (0 if r['hur'] == 'deltopp' else 9e9)
# Samma namn på flera toppar: den högsta behåller namnet om den inte ligger mer än dubbelt så långt från namnet som den närmaste
# Samma namn på flera toppar: namnet behålls av den som ligger närmast namnet, de andra blir "nära …"
for namn in {r['namn'] for r in valda if r['namn'] and not ((r['hur'] in ('handrättat', 'OSM', 'Wikipedia') or r['hur'].startswith('Topo10')) or r['hur'].startswith('Topo10'))}:
    samma = [r for r in valda if r['namn'] == namn and not ((r['hur'] in ('handrättat', 'OSM', 'Wikipedia') or r['hur'].startswith('Topo10')) or r['hur'].startswith('Topo10'))]
    if len(samma) < 2: continue
    narmast = min(r['avst'] for r in samma)
    vinnare = max([r for r in samma if r['avst'] <= 2 * narmast + 300], key=lambda r: r['hojd'])
    for r in samma:
        if r is not vinnare: r['namn'], r['hur'] = '', 'nära ' + namn
# Automatiska namn som krockar med ett handrättat namn blir "nära …"
hand = {r['namn'] for r in valda if (r['hur'] in ('handrättat', 'OSM', 'Wikipedia') or r['hur'].startswith('Topo10'))}
for r in valda:
    if not ((r['hur'] in ('handrättat', 'OSM', 'Wikipedia') or r['hur'].startswith('Topo10')) or r['hur'].startswith('Topo10')) and r['namn'] in hand: r['namn'], r['hur'] = '', 'nära ' + r['namn']
# Visningsnamn för toppar utan eget namn: "Topp 2007 m nära Ruopsoktjåhkkå"
for r in valda:
    r['visning'] = r['namn'] or (f"Topp {r['hojd']} m " + r['hur']).replace(' nära –', '')
with open(os.path.join(KOD, 'toppar.csv'), 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['objektidentitet', 'namn', 'eget_namn', 'namnkalla', 'hojd', 'rang', 'lan', 'lannamn', 'lanrang', 'typ', 'prim30', 'x', 'y'])
    for r in valda:
        w.writerow([r['oid'], r['visning'], 'ja' if r['namn'] else 'nej', r['hur'], r['hojd'], riket.get(r['fid'], ''), r['lan'], r['lannamn'],
                    lanrang.get(r['fid'], ''), r['typ'], r['prim30'] or 'okänd', r['x'], r['y']])
print('valda', len(valda), '| riket', len(riket), '| län', len(lanrang), '| utan eget namn', sum(1 for r in valda if not r['namn']))
