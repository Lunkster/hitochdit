#!/usr/bin/env python3
"""Hämtar kristna kyrkobyggnader i Sverige från OpenStreetMap (Overpass) och skriver en CSV för import.
Används av tools/ladda_osm_kyrkor.sh. Bara standardbiblioteket.

Kolumnen 'regel' anger varför objektet räknas som Svenska kyrkan:
  explicit = denomination lutheran/church_of_sweden eller operator/brand/network = Svenska kyrkan
  okand    = saknar samfundsuppgift men heter "... kyrka"/"... kapell" (tas inte med nu, räknas bara)
  annan    = annat samfund (tas inte med)
"""
import csv, json, re, sys, time, urllib.error, urllib.parse, urllib.request

FRAGA = """[out:json][timeout:600][maxsize:536870912];
area["ISO3166-1"="SE"][admin_level=2]->.se;
( nwr["amenity"="place_of_worship"]["religion"="christian"](area.se);
  nwr["building"="church"](area.se); );
out center tags;"""
# Overpass-servrar att prova i tur och ordning (de kan vara överbelastade – 504/429 – och då provar vi nästa)
SERVRAR = ["https://overpass-api.de/api/interpreter",
           "https://overpass.private.coffee/api/interpreter",
           "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
           "https://overpass.kumi.systems/api/interpreter"]
ANDRA = re.compile(r"pingst|baptist|missions|equmenia|metodist|katolsk|catholic|ortodox|orthodox|adventist|frälsnings|"
                   r"evangeliska frikyrkan|efk|jehova|mormon|sista dagars|vineyard|livets ord|filadelfia|betel|elim|salem", re.I)

def regel(t):
    d = (t.get("denomination") or "").lower()
    op = " ".join(t.get(k, "") for k in ("operator", "brand", "network", "owner")).lower()
    namn = t.get("name", "")
    if d in ("lutheran", "church_of_sweden", "evangelical_lutheran") or "svenska kyrkan" in op or "church of sweden" in op:
        return "explicit"
    if d or ANDRA.search(namn) or ANDRA.search(op):
        return "annan"
    if re.search(r"(kyrka|kapell)$", namn.strip(), re.I):
        return "okand"
    return "annan"

def main(ut):
    data = urllib.parse.urlencode({"data": FRAGA}).encode()
    el = None
    for forsok in range(2):
        for url in SERVRAR:
            print(f"→ Frågar OpenStreetMap via {url.split('/')[2]} – kan ta några minuter …", file=sys.stderr)
            req = urllib.request.Request(url, data=data, headers={"User-Agent": "hitochdit-laddskript (privat hobbyapp)"})
            try:
                with urllib.request.urlopen(req, timeout=700) as r:
                    el = json.load(r)["elements"]
                break
            except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
                print(f"  ✗ {e} – provar nästa", file=sys.stderr)
        if el is not None:
            break
        print("  Alla servrar upptagna, väntar 60 s och försöker igen …", file=sys.stderr)
        time.sleep(60)
    if el is None:
        sys.exit("Kunde inte hämta från OpenStreetMap just nu. Försök igen om en stund.")
    n = 0
    with open(ut, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["osm_id", "namn", "lat", "lon", "denomination", "operator", "regel"])
        for e in el:
            t = e.get("tags", {})
            if not t.get("name"):
                continue
            lat = e.get("lat", e.get("center", {}).get("lat"))
            lon = e.get("lon", e.get("center", {}).get("lon"))
            if lat is None or lon is None:
                continue
            w.writerow([f'{e["type"]}/{e["id"]}', t["name"], lat, lon, t.get("denomination", ""), t.get("operator", ""), regel(t)])
            n += 1
    print(f"→ {len(el)} objekt från OSM, {n} med namn skrivna till {ut}", file=sys.stderr)

if __name__ == "__main__":
    main(sys.argv[1])
