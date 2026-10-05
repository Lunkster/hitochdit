#!/usr/bin/env bash
# Laddar Sveriges 300 största tätorter (efter folkmängd) från SCB:s GeoPackage till Supabase (tabellen objekt, kalla = TA).
# Kräver att supabase/12_geografi.sql körts en gång. Filen laddas ner manuellt från SCB – se Obsidian: Hit och Dit - Geodata.
# Kör:  bash ~/Dokument/Claude/HitochDit/kod/hitochdit/tools/ladda_tatorter.sh [sökväg till .gpkg]
source "$(dirname "$0")/geodata.sh"

GPKG="${1:-$REPO/../Tatorter_2023.gpkg}"
[[ -f "$GPKG" ]] || { echo "Hittar inte $GPKG – ange sökvägen som argument." >&2; exit 1; }
LAGER="$(ogrinfo -ro -q "$GPKG" | sed -nE 's/^[0-9]+: ([^ ]+).*/\1/p' | head -n1)"

echo "→ Läser de 300 största tätorterna ur $(basename "$GPKG") (lager $LAGER)"
# Bara de 300 största förs över – resten behövs inte i databasen. Förenklas ~5 m redan här (SWEREF 99 TM, meter).
ogr2ogr -f PostgreSQL "PG:${HITOCHDIT_DB}" "$GPKG" -sql "SELECT * FROM \"$LAGER\" ORDER BY bef DESC LIMIT 300" \
  -nln import.scb_tatorter -overwrite -simplify 5 -t_srs EPSG:4326 -nlt PROMOTE_TO_MULTI \
  -lco GEOMETRY_NAME=geom -lco FID=ogc_fid -lco SPATIAL_INDEX=NONE
kor_sql "supabase/ladda/tatorter.sql"
echo "✓ Klart."
