# Gemensamma inställningar för laddskripten. Läses in av tools/ladda_*.sh – körs inte själv.
set -euo pipefail

KONF="${HOME}/.config/hitochdit/db.env"     # ligger på din dator, ALDRIG i repot
if [[ ! -f "$KONF" ]]; then
  echo "Saknar $KONF – se Obsidian: Hit och Dit - Geodata (steg 2)." >&2; exit 1
fi
# shellcheck disable=SC1090
source "$KONF"
: "${HITOCHDIT_DB:?HITOCHDIT_DB saknas i $KONF}"

for prog in ogr2ogr psql; do
  command -v "$prog" >/dev/null || { echo "Saknar $prog – kör: sudo apt install gdal-bin postgresql-client" >&2; exit 1; }
done

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PGCLIENTENCODING=UTF8
# WFS-sidindelning så att stora datamängder hämtas i omgångar
OGR_WFS=(--config OGR_WFS_PAGING_ALLOWED ON --config OGR_WFS_PAGE_SIZE 5000 --config OGR_WFS_LOAD_MULTIPLE_LAYER_DEFN NO)

# ladda_wfs <wfs-url> <lager> <importtabell>
ladda_wfs () {
  # Lagernamnet kan ha arbetsytans prefix (t.ex. Varldsarv_ogc:varldsarv_sverige) – leta upp rätt variant
  local lager
  lager="$(ogrinfo "${OGR_WFS[@]}" -ro -q "WFS:$1" 2>/dev/null | sed -nE 's/^[0-9]+: ([^ ]+).*/\1/p' | grep -E "(^|:)$2\$" | head -n1 || true)"
  lager="${lager:-$2}"
  echo "→ Hämtar $lager från $1"
  ogr2ogr "${OGR_WFS[@]}" -f PostgreSQL "PG:${HITOCHDIT_DB}" "WFS:$1" "$lager" \
    -nln "import.$3" -overwrite -t_srs EPSG:4326 -nlt PROMOTE_TO_MULTI \
    -lco GEOMETRY_NAME=geom -lco FID=ogc_fid -lco SPATIAL_INDEX=NONE -progress
}
# kor_sql <fil>
kor_sql () {
  echo "→ Kör $1"
  psql "$HITOCHDIT_DB" -v ON_ERROR_STOP=1 -q -f "$REPO/$1"
}
