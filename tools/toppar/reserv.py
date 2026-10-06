"""Reservregel för punkter där höjdkurvorna inte gick att sluta (topp/prim30 oavgjorda i resultat.csv):
topp      = ingen höjdkurva högre än punkten och ingen högre höjdpunkt inom 1 km
isolerad  = närmaste högre höjdpunkt ligger minst 1,5 km bort (ersätter primärfaktor, markeras 'okänd')
Lägger till kolumnen 'reserv' i resultat.csv: topp+isolerad | topp | nej"""
import csv, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import analys as A
from gpkg import wkb
f = sys.argv[1] if len(sys.argv) > 1 else os.path.join(A.KOD, 'toppar_resultat.csv')
R = list(csv.DictReader(open(f)))
pk = [(wkb(g)[1][0], wkb(g)[1][1], h) for h, g in A.c.execute("select cast(hojdvarde as int), geom from hojdpunkt")]
for r in R:
    r.setdefault('reserv', '')
    if not (r['topp'] == '' or (r['topp'] == 'True' and r['prim30'] == '')): continue
    x, y, h = int(r['x']), int(r['y']), int(r['hojd'])
    hogre_kurva = any(True for _ in A.linjer(x - 1000, y - 1000, x + 1000, y + 1000, over=h))
    hogre = [math.dist((x, y), q[:2]) for q in pk if q[2] > h and abs(q[0] - x) < 20000 and abs(q[1] - y) < 20000]
    narmast = min(hogre) if hogre else 9e9
    topp = r['topp'] == 'True' or (not hogre_kurva and narmast > 1000)
    r['reserv'] = 'topp+isolerad' if topp and narmast >= 1500 else ('topp' if topp else 'nej')
with open(f, 'w', newline='') as fh:
    w = csv.DictWriter(fh, fieldnames=list(R[0].keys())); w.writeheader(); w.writerows(R)
from collections import Counter
print(Counter(r['reserv'] for r in R if r['reserv']))
