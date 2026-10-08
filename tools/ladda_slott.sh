#!/usr/bin/env bash
# Laddar slott och herrgårdar (SH) till Supabase från RAÄ:s nedladdade filer (GeoPackage) – ingen WFS behövs.
#   byggnadsminnen_skyddsomraden_sverige.gpkg och kulturhistoriskt_inventerad_bebyggelse_sverige.gpkg
# Filerna ligger i ~/Dokument/Geodata (ändra med GEODATA=/annan/mapp).
# Kör:  bash ~/Dokument/Claude/HitochDit/kod/hitochdit/tools/ladda_slott.sh
source "$(dirname "$0")/geodata.sh"
GEODATA="${GEODATA:-$HOME/Dokument/Geodata}"

# ladda_fil <fil> <importtabell> [attributfilter]
ladda_fil () {
  [[ -f "$1" ]] || { echo "Hittar inte $1" >&2; exit 1; }
  echo "→ Läser $(basename "$1")"
  ogr2ogr -f PostgreSQL "PG:${HITOCHDIT_DB}" "$1" -nln "import.$2" -overwrite -t_srs EPSG:4326 -nlt PROMOTE_TO_MULTI \
    -lco GEOMETRY_NAME=geom -lco FID=ogc_fid -lco SPATIAL_INDEX=NONE ${3:+-where "$3"}
}

# Byggnadsminnen (skyddsområden) som fortfarande gäller
ladda_fil "$GEODATA/byggnadsminnen_skyddsomraden_sverige.gpkg" "sh_bm" "havt_skydd = 0"
# Byggnader och miljöer som kan vara slott eller herrgårdar (urvalet görs i SQL-steget)
ladda_fil "$GEODATA/kulturhistoriskt_inventerad_bebyggelse_sverige.gpkg" "sh_beb" \
  "andamal_huvudkategori IN ('Slott', 'Mangårdsbyggnad') OR andamal_underkategori IN ('Herrgårdsmiljö', 'Slottsmiljö')"
kor_sql "supabase/ladda/slott.sql"
echo "✓ Klart."
