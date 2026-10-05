#!/usr/bin/env bash
# Laddar kommuner och län från Lantmäteriets GeoPackage (kommun-lan-rike) till Supabase (tabellen indelning)
# och fyller i kommun/län på alla besök. Kräver att supabase/11_indelning.sql körts en gång.
# Filen laddas ner manuellt från Lantmäteriets Geotorget (inloggning) – se Obsidian: Hit och Dit - Geodata.
# Kör:  bash ~/Dokument/Claude/HitochDit/kod/hitochdit/tools/ladda_indelning.sh [sökväg till .gpkg]
source "$(dirname "$0")/geodata.sh"

GPKG="${1:-$REPO/../kommun-lan-rike_aktuell/kommun-lan-rike_aktuell.gpkg}"
[[ -f "$GPKG" ]] || { echo "Hittar inte $GPKG – ange sökvägen som argument." >&2; exit 1; }

for lager in kommun lan; do
  echo "→ Läser $lager från $(basename "$GPKG")"
  ogr2ogr -f PostgreSQL "PG:${HITOCHDIT_DB}" "$GPKG" "$lager" -nln "import.lm_$lager" -overwrite \
    -t_srs EPSG:4326 -nlt PROMOTE_TO_MULTI -lco GEOMETRY_NAME=geom -lco FID=ogc_fid -lco SPATIAL_INDEX=NONE
done
kor_sql "supabase/ladda/indelning.sql"
echo "✓ Klart."
