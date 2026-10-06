#!/usr/bin/env bash
# Laddar topparna (300 högsta + 5 högsta per län) från kod/Toppar.gpkg (eller kod/toppar.csv) till Supabase (tabellen objekt, kalla = TO).
# toppar.csv tas fram med tools/toppar/analys.py + namn.py (se tools/toppar/LASMIG.md). Kräver supabase/15_toppar.sql.
# Kör:  bash ~/Dokument/Claude/HitochDit/kod/hitochdit/tools/ladda_toppar.sh [sökväg till Toppar.gpkg]
source "$(dirname "$0")/geodata.sh"
# Källa: senaste Toppar_v3/v2.gpkg (eller Toppar.gpkg) – namnen rättade för hand i QGIS; annars toppar.csv
FIL="${1:-$REPO/../Toppar_v3.gpkg}"
[[ -f "$FIL" ]] || FIL="$REPO/../Toppar_v2.gpkg"
[[ -f "$FIL" ]] || FIL="$REPO/../Toppar.gpkg"
[[ -f "$FIL" ]] || FIL="$REPO/../toppar.csv"
[[ -f "$FIL" ]] || { echo "Hittar varken Toppar.gpkg eller toppar.csv" >&2; exit 1; }
echo "→ Läser $(basename "$FIL")"
if [[ "$FIL" == *.gpkg ]]; then
  ogr2ogr -f PostgreSQL "PG:${HITOCHDIT_DB}" "$FIL" -sql "SELECT objektidentitet, namn, hojd, rang, lan, lannamn, lanrang, typ, prim30, x, y FROM toppar" \
    -dialect SQLite -nln import.toppar -overwrite -nlt NONE -lco FID=ogc_fid
else
psql "$HITOCHDIT_DB" -v ON_ERROR_STOP=1 -q <<SQL
create schema if not exists import;
drop table if exists import.toppar;
create table import.toppar (objektidentitet text, namn text, eget_namn text, namnkalla text, hojd int, rang int, lan text, lannamn text,
                            lanrang int, typ text, prim30 text, x double precision, y double precision);
\copy import.toppar from '$FIL' with (format csv, header true)
SQL
fi
kor_sql "supabase/ladda/toppar.sql"
echo "✓ Klart."
