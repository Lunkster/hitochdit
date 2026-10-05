#!/usr/bin/env bash
# Laddar socknar och städer från Lantmäteriets GeoPackage (Sockenstad) till Supabase (tabellen indelning, typ = socken)
# och fyller i socken på alla besök. Kräver att supabase/11_indelning.sql och 13_socknar.sql körts en gång,
# och att kommuner/län är laddade (länet räknas fram ur dem).
# Filen laddas ner manuellt från Lantmäteriets Geotorget – se Obsidian: Hit och Dit - Geodata.
# Kör:  bash ~/Dokument/Claude/HitochDit/kod/hitochdit/tools/ladda_socknar.sh [sökväg till .gpkg]
source "$(dirname "$0")/geodata.sh"

GPKG="${1:-$REPO/../sockenstad/sockenstad.gpkg}"
[[ -f "$GPKG" ]] || { echo "Hittar inte $GPKG – ange sökvägen som argument." >&2; exit 1; }

echo "→ Läser sockenstad från $(basename "$GPKG")"
# Förenklas ~10 m redan här (SWEREF 99 TM, meter) – samma nivå som kommungränserna
ogr2ogr -f PostgreSQL "PG:${HITOCHDIT_DB}" "$GPKG" sockenstad -nln import.lm_sockenstad -overwrite \
  -simplify 10 -t_srs EPSG:4326 -nlt PROMOTE_TO_MULTI -lco GEOMETRY_NAME=geom -lco FID=ogc_fid -lco SPATIAL_INDEX=NONE
kor_sql "supabase/ladda/socknar.sql"
echo "✓ Klart."
