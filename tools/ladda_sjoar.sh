#!/usr/bin/env bash
# Laddar Sveriges 300 största insjöar från SMHI:s Vattenytor 2016 (SVAR) till Supabase (tabellen objekt, kalla = SJ).
# Kräver att supabase/12_geografi.sql körts en gång.
# Kör:  bash ~/Dokument/Claude/HitochDit/kod/hitochdit/tools/ladda_sjoar.sh
#
# Urval: ytkod 50 (sjö) och 51 (sjö utan synligt utlopp) – inte vattendrag (60), havsvikar (70) m.m.
# En sjö kan bestå av flera vattenytor (Vänern har 27) – de slås ihop på SMHI:s sjö-id (SJOID).
# För att inte hämta alla 42 000 ytor ber vi servern bara om ytor större än 1 km² (CQL-filter), i sidor om 500.
source "$(dirname "$0")/geodata.sh"
command -v curl >/dev/null || { echo "Saknar curl – kör: sudo apt install curl" >&2; exit 1; }

URL="https://opendata-view.smhi.se/SMHI_vatten/Vattenytor_2016/ows"
FILTER="YTKOD IN (50,51) AND area(the_geom) > 1000000"
SIDA=500
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

start=0; n=0; totalt=0
while :; do
  f="$TMP/sida_$n.json"
  echo "→ Hämtar vattenytor från nr $start hos SMHI"
  curl -fsS --retry 3 -G "$URL" -o "$f" \
    --data-urlencode "service=WFS" --data-urlencode "version=2.0.0" --data-urlencode "request=GetFeature" \
    --data-urlencode "typeNames=SMHI_vatten:Vattenytor_2016" --data-urlencode "outputFormat=application/json" \
    --data-urlencode "srsName=EPSG:3006" --data-urlencode "sortBy=OBJECTID" \
    --data-urlencode "count=$SIDA" --data-urlencode "startIndex=$start" --data-urlencode "cql_filter=$FILTER"
  antal="$(ogrinfo -ro -so -al "$f" 2>/dev/null | sed -nE 's/^Feature Count: ([0-9]+).*/\1/p' | head -n1)"
  antal="${antal:-0}"
  [[ "$antal" -gt 0 ]] || break
  # Förenkla ~10 m i SWEREF 99 TM (meter) innan det skickas till databasen
  ogr2ogr -f PostgreSQL "PG:${HITOCHDIT_DB}" "$f" -nln import.smhi_vattenytor \
    $([[ $n -eq 0 ]] && echo "-overwrite -lco GEOMETRY_NAME=geom -lco FID=ogc_fid -lco SPATIAL_INDEX=NONE" || echo "-append") \
    -s_srs EPSG:3006 -t_srs EPSG:4326 -simplify 10 -nlt PROMOTE_TO_MULTI
  # Gå vidare med så många som faktiskt kom (servern kan ha ett lägre tak än $SIDA); slut när en sida är tom
  totalt=$((totalt + antal)); start=$((start + antal)); n=$((n + 1))
done
echo "→ $totalt vattenytor hämtade"
[[ "$totalt" -gt 0 ]] || { echo "Inga vattenytor hämtades – kontrollera adressen/filtret." >&2; exit 1; }
kor_sql "supabase/ladda/sjoar.sql"
echo "✓ Klart."
