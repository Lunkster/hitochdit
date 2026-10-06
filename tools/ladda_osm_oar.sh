#!/usr/bin/env bash
# TEST: Sveriges 300 största öar ur OpenStreetMap (place=island), både i havet och i sjöar.
#   Utan argument: hämtar, bygger ytor, rangordnar och skriver en RAPPORT – appens data rörs inte.
#   Med --ladda:   lägger dessutom in de 300 största i tabellen objekt (kalla = OE, kategori geografi).
#   Med --igen:    hämtar inte från OpenStreetMap igen utan använder förra hämtningen (import.osm_oar_linjer).
# Kräver att supabase/12_geografi.sql körts.
# Kör:  bash ~/Dokument/Claude/HitochDit/kod/hitochdit/tools/ladda_osm_oar.sh [--igen] [--ladda]
source "$(dirname "$0")/geodata.sh"
LADDA=0; IGEN=0
for a in "$@"; do case "$a" in --ladda) LADDA=1 ;; --igen) IGEN=1 ;; *) echo "Okänt argument: $a" >&2; exit 1 ;; esac; done

if [[ $IGEN -eq 1 ]]; then
  echo "→ Använder förra hämtningen från OpenStreetMap"
else
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
python3 "$REPO/tools/osm_oar.py" "$TMP/osm_oar.csv"
echo "→ Skickar linjerna till databasen ($(du -h "$TMP/osm_oar.csv" | cut -f1))"
psql "$HITOCHDIT_DB" -v ON_ERROR_STOP=1 -q <<SQL
create schema if not exists import;
drop table if exists import.osm_oar_linjer;
create table import.osm_oar_linjer (osm_typ text, osm_id bigint, namn text, roll text, wkt text);
\copy import.osm_oar_linjer from '$TMP/osm_oar.csv' with (format csv, header true)
SQL
fi
kor_sql "supabase/ladda/osm_oar_rapport.sql"
if [[ $LADDA -eq 1 ]]; then
  kor_sql "supabase/ladda/osm_oar.sql"
else
  echo "ℹ Bara rapport. Ser listan bra ut: kör igen med --ladda för att lägga in öarna i appen."
fi
echo "✓ Klart."
