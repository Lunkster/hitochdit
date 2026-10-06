#!/usr/bin/env python3
"""Hämtar öar (place=island) i Sverige från OpenStreetMap (Overpass) som linjer med geometri och skriver en CSV.
Används av tools/ladda_osm_oar.sh. Bara standardbiblioteket. Ytorna byggs sedan ihop i PostGIS (ST_BuildArea).

Rader: osm_typ (way/relation), osm_id, namn, roll (outer/inner/''), wkt (LINESTRING i WGS84)
"""
import csv, json, sys, time, urllib.error, urllib.parse, urllib.request

FRAGA = """[out:json][timeout:900][maxsize:1073741824];
area["ISO3166-1"="SE"][admin_level=2]->.se;
( way["place"="island"](area.se);
  relation["place"="island"](area.se); );
out geom;"""
SERVRAR = ["https://overpass-api.de/api/interpreter",
           "https://overpass.private.coffee/api/interpreter",
           "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
           "https://overpass.kumi.systems/api/interpreter"]

def wkt(punkter):
    pts = [(p["lon"], p["lat"]) for p in punkter if p]
    return "LINESTRING(" + ",".join(f"{x:.7f} {y:.7f}" for x, y in pts) + ")" if len(pts) >= 2 else None

def main(ut):
    data = urllib.parse.urlencode({"data": FRAGA}).encode()
    el = None
    for forsok in range(2):
        for url in SERVRAR:
            print(f"→ Frågar OpenStreetMap via {url.split('/')[2]} – kan ta några minuter …", file=sys.stderr)
            req = urllib.request.Request(url, data=data, headers={"User-Agent": "hitochdit-laddskript (privat hobbyapp)"})
            try:
                with urllib.request.urlopen(req, timeout=1000) as r:
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
    n_way = n_rel = rader = 0
    with open(ut, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["osm_typ", "osm_id", "namn", "roll", "wkt"])
        for e in el:
            t = e.get("tags", {})
            namn = t.get("name:sv") or t.get("name") or ""
            if e["type"] == "way":
                g = wkt(e.get("geometry", []))
                if g: w.writerow(["way", e["id"], namn, "", g]); n_way += 1; rader += 1
            elif e["type"] == "relation":
                n_rel += 1
                for m in e.get("members", []):
                    if m.get("type") != "way": continue
                    g = wkt(m.get("geometry", []))
                    if g: w.writerow(["relation", e["id"], namn, m.get("role", ""), g]); rader += 1
    print(f"→ {n_way} öar som enkla ytor + {n_rel} som relationer ({rader} linjer)", file=sys.stderr)

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "osm_oar.csv")
