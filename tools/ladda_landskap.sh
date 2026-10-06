#!/usr/bin/env bash
# Laddar Sveriges 25 landskap till Supabase (tabellen indelning, typ = landskap) och fyller i landskap på alla besök.
# Källa: Per Liedmans "svenska-landskap" (GitHub, CC0) – byggd på Lantmäteriets Distriktskarta, förenklad 5 m. OKLIPPT version (täcker även vatten) – så att öar, skär och båtar i skärgården hamnar i rätt landskap.
# Hämtas automatiskt till kod/svenska-landskap.geo.json om filen saknas. Kräver supabase/16_landskap.sql.
# Kör:  bash ~/Dokument/Claude/HitochDit/kod/hitochdit/tools/ladda_landskap.sh [sökväg till geojson]
source "$(dirname "$0")/geodata.sh"
URL="https://github.com/perliedman/svenska-landskap/raw/refs/heads/master/svenska-landskap.geo.json"
FIL="${1:-$REPO/../svenska-landskap.geo.json}"
if [[ ! -f "$FIL" ]]; then
  echo "→ Hämtar $(basename "$URL") från GitHub"
  curl -fsSL "$URL" -o "$FIL"
fi
head -c 1 "$FIL" | grep -q '{' || { echo "$FIL är inte GeoJSON (kanske en webbsida) – ta bort den och kör igen." >&2; exit 1; }
echo "→ Läser $(basename "$FIL")"
ogr2ogr -f PostgreSQL "PG:${HITOCHDIT_DB}" "$FIL" -nln import.landskap -overwrite \
  -t_srs EPSG:4326 -nlt PROMOTE_TO_MULTI -lco GEOMETRY_NAME=geom -lco FID=ogc_fid -lco SPATIAL_INDEX=NONE
kor_sql "supabase/ladda/landskap.sql"
echo "✓ Klart."
